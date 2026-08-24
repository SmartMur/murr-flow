import AVFoundation
import Foundation
import MurrFlowTranscript
import Speech

/// Streaming on-device transcription via the classic `SFSpeechRecognizer` API.
///
/// This is the fallback for Macs where the macOS 26 `SpeechAnalyzer` stack does not
/// exist — in practice every Intel Mac, where `SpeechTranscriber.isAvailable` is false
/// and `installedLocales` is empty. `SFSpeechRecognizer` has shipped since macOS 10.15
/// on both architectures, streams partial results for live HUD text, and supports
/// on-device recognition for the dictation locales.
///
/// Selection is automatic: `AppleSpeechSupport.isAvailable` decides which engine backs
/// the user's "Apple" choice. The user never picks "legacy" — on a Mac without the new
/// stack, this *is* Apple's engine.
///
/// ## One hold is many recognition tasks
///
/// The API is built around utterances, not around a key being held. It finalizes whenever
/// it decides speech paused, and a task stops at roughly a minute whatever you do. So a
/// hold is served by a *series* of tasks, each tagged with a segment index, and
/// `TranscriptSession` stitches their results back into one transcript in the right order.
/// This engine owns only the `Speech` objects and the rotation timer; every decision about
/// what to show and when the dictation is over lives in that value type, where it can be
/// tested without a microphone.
actor LegacySpeechEngine: TranscriptionEngine {
    /// A recognition task is cut off at about 60s. Rotating at 50 leaves room for the
    /// final result of the outgoing task to arrive before the ceiling does.
    private static let defaultRotationInterval = Duration.seconds(50)

    private let locale: Locale
    private let rotationInterval: Duration

    private var recognizer: SFSpeechRecognizer?
    private var chunkContinuation: AsyncThrowingStream<TranscriptionChunk, Error>.Continuation?

    private var session = TranscriptSession()
    /// The live recognition request and task per segment index. A rotated-away segment
    /// stays here until its final result lands, because cancelling it would discard that.
    private var requests: [Int: SFSpeechAudioBufferRecognitionRequest] = [:]
    private var tasks: [Int: SFSpeechRecognitionTask] = [:]
    /// The segment audio is currently routed to.
    private var openSegment: Int?
    private var rotationTask: Task<Void, Never>?
    /// Read once at `start()`, because `startTask` runs per segment and must not hop to
    /// the main actor in the middle of a hold.
    private var biasPhrases: [String] = []
    /// Audio that arrived while no segment was open.
    ///
    /// There is one async hop between the recognizer reporting a final and this actor
    /// opening the replacement task, and a speaker who pauses only briefly is already
    /// talking again inside it. Holding those buffers and flushing them into the next
    /// request is the difference between losing the first word after every pause and
    /// losing nothing. Capped because a hold that ends with no segment ever reopening
    /// must not grow this without bound.
    private var orphanedAudio: [AudioChunk] = []
    private static let orphanLimit = 64
    /// Segments that have actually had audio appended to them.
    private var segmentsWithAudio: Set<Int> = []

    init(
        locale: Locale = Locale.current,
        rotationInterval: Duration = LegacySpeechEngine.defaultRotationInterval
    ) {
        self.locale = locale
        self.rotationInterval = rotationInterval
    }

    /// 16 kHz mono float32 — comfortably within what `SFSpeechRecognizer` accepts, and
    /// cheap for `AudioCapture` to convert to from any mic's native format.
    func preferredInputFormat() async -> AVAudioFormat? {
        AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)
    }

    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error> {
        guard await Self.ensureAuthorized() else {
            throw TranscriptionError.speechRecognitionDenied
        }

        // Fall back to en-US the same way AppleSpeechEngine resolves locales, rather
        // than failing on a regional variant the recognizer doesn't list (en-CA → en-US).
        let recognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptionError.localeUnsupported(locale)
        }
        self.recognizer = recognizer

        let (chunks, continuation) = AsyncThrowingStream<TranscriptionChunk, Error>.makeStream()
        chunkContinuation = continuation

        biasPhrases = await MainActor.run { DictionaryStore.shared.biasPhrases }

        Log.speech.info("SFSpeechRecognizer started — locale \(recognizer.locale.identifier, privacy: .public), onDevice \(recognizer.supportsOnDeviceRecognition, privacy: .public)")

        session = TranscriptSession()
        apply(session.start())

        return chunks
    }

    func feed(_ chunk: AudioChunk) async {
        guard let openSegment, let request = requests[openSegment] else {
            if orphanedAudio.count < Self.orphanLimit { orphanedAudio.append(chunk) }
            return
        }
        segmentsWithAudio.insert(openSegment)
        request.append(chunk.buffer)
    }

    func finish() async {
        let trailing = openSegment
        apply(session.handle(.finishRequested))

        // A pause right before the key came up leaves a freshly-opened segment that never
        // heard anything. Its request would eventually answer `endAudio` with a "no speech"
        // error, but making every paste wait out that round trip is pointless.
        if let trailing, !segmentsWithAudio.contains(trailing) {
            apply(session.handle(.abandoned(segment: trailing)))
            discard(trailing)
        }

        // The outgoing task's final result arrives through its handler after `endAudio`.
        // Give it a bounded moment; a recognizer that dies silently must not hang the key
        // release, and whatever has already been committed is still worth pasting.
        for _ in 0..<40 where !session.isFinished {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if !session.isFinished {
            Log.speech.error("final result never arrived; pasting what was committed")
            apply(session.forceComplete())
        }

        teardown()
    }

    // MARK: - Driving the session

    private func apply(_ actions: [TranscriptSession.Action]) {
        for action in actions {
            switch action {
            case .emit(let text):
                chunkContinuation?.yield(TranscriptionChunk(text: text, isFinal: false))

            case .openSegment(let index):
                openSegment = index
                startTask(for: index)
                scheduleRotation()

            case .closeSegment(let index):
                requests[index]?.endAudio()

            case .complete(let text):
                chunkContinuation?.yield(TranscriptionChunk(text: text, isFinal: true))
                chunkContinuation?.finish()
                chunkContinuation = nil
            }
        }
    }

    /// Opens a recognition request and task for one segment.
    ///
    /// Each segment gets its own request because `SFSpeechAudioBufferRecognitionRequest`
    /// is single-use: once it has finalized, appending more audio to it does nothing at
    /// all, silently. That silence is the original bug.
    private func startTask(for index: Int) {
        guard let recognizer else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device when the OS supports it for this locale; otherwise Apple's server.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.taskHint = .dictation
        // Same dictionary nudge AppleSpeechEngine applies via AnalysisContext.
        if !biasPhrases.isEmpty { request.contextualStrings = biasPhrases }
        requests[index] = request

        // Whatever was said between the last segment finalizing and this one existing.
        for chunk in orphanedAudio { request.append(chunk.buffer) }
        orphanedAudio.removeAll(keepingCapacity: true)

        // The result handler arrives on an arbitrary queue, and neither
        // `SFSpeechRecognitionResult` nor `Error` is Sendable. Flatten both into plain
        // value types here, on the callback's own thread, then hop onto the actor with
        // data that can legally cross the boundary.
        tasks[index] = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            let outcome: Outcome
            if let result {
                outcome = .text(result.bestTranscription.formattedString, isFinal: result.isFinal)
            } else if let error {
                let nsError = error as NSError
                outcome = .failure(
                    domain: nsError.domain,
                    code: nsError.code,
                    message: error.localizedDescription
                )
            } else {
                return
            }
            Task { await self.handle(outcome, segment: index) }
        }
    }

    /// Restarts the countdown to the next rotation.
    ///
    /// Anchored to the opening of a segment rather than to the start of the hold, because
    /// the ceiling applies per recognition task. A pause that ends a segment early resets
    /// it for free.
    private func scheduleRotation() {
        rotationTask?.cancel()
        let interval = rotationInterval
        rotationTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await self?.rotate()
        }
    }

    private func rotate() {
        Log.speech.info("rotating recognition task before the ~60s ceiling")
        apply(session.handle(.rotationDue))
    }

    private func teardown() {
        rotationTask?.cancel()
        rotationTask = nil
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        requests.removeAll()
        openSegment = nil
        segmentsWithAudio.removeAll()
        orphanedAudio.removeAll(keepingCapacity: false)
        recognizer = nil
        if let continuation = chunkContinuation {
            chunkContinuation = nil
            continuation.finish()
        }
    }

    // MARK: - Result handling

    /// A recognizer callback reduced to Sendable values.
    private enum Outcome: Sendable {
        case text(String, isFinal: Bool)
        case failure(domain: String, code: Int, message: String)
    }

    private func handle(_ outcome: Outcome, segment: Int) {
        switch outcome {
        case .text(let text, let isFinal):
            apply(session.handle(isFinal ? .finalized(segment: segment, text: text)
                                         : .revised(segment: segment, text: text)))
            if isFinal { discard(segment) }

        case .failure(let domain, let code, let message):
            // endAudio() surfaces a benign "no speech detected" cancellation on empty
            // recordings, and a rotated-away task reports one routinely. Neither is worth
            // failing the whole dictation over: drop the segment and keep the rest.
            let benign = domain == "kAFAssistantErrorDomain" && [203, 216, 1110].contains(code)
            if !benign {
                Log.speech.error("SFSpeechRecognizer failed on segment \(segment, privacy: .public): \(message, privacy: .public)")
            }
            apply(session.handle(.abandoned(segment: segment)))
            discard(segment)

            // A failure on the segment that was taking audio leaves the hold with nowhere
            // to put it. Only a real failure warrants ending the dictation; a benign
            // cancellation of an already-replaced segment does not.
            if !benign, openSegment == segment, !session.isFinished {
                apply(session.forceComplete())
                teardown()
            }
        }
    }

    private func discard(_ segment: Int) {
        tasks[segment]?.cancel()
        tasks[segment] = nil
        requests[segment] = nil
    }

    // MARK: - Authorization

    /// Speech recognition has its own TCC grant, separate from the microphone.
    /// `NSSpeechRecognitionUsageDescription` is already in Info.plist.
    private static func ensureAuthorized() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default: return false
        }
    }
}

/// Which "Apple" implementation this Mac gets.
///
/// The macOS 26 `SpeechAnalyzer` stack only exists on Apple Silicon; on Intel,
/// `SpeechTranscriber.isAvailable` is false and its locale lists are empty. Checked
/// once — the answer can't change while the process lives.
enum AppleSpeechSupport {
    static let hasSpeechAnalyzer: Bool = SpeechTranscriber.isAvailable
}
