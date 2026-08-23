import AVFoundation
import Foundation
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
actor LegacySpeechEngine: TranscriptionEngine {
    private let locale: Locale

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var chunkContinuation: AsyncThrowingStream<TranscriptionChunk, Error>.Continuation?

    init(locale: Locale = Locale.current) {
        self.locale = locale
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

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device when the OS supports it for this locale; otherwise Apple's server.
        // Logged publicly so a field transcript shows which path ran.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.taskHint = .dictation
        // Same dictionary nudge AppleSpeechEngine applies via AnalysisContext.
        let phrases = await MainActor.run { DictionaryStore.shared.biasPhrases }
        if !phrases.isEmpty { request.contextualStrings = phrases }
        self.request = request

        let (chunks, continuation) = AsyncThrowingStream<TranscriptionChunk, Error>.makeStream()
        chunkContinuation = continuation

        Log.speech.info("SFSpeechRecognizer started — locale \(recognizer.locale.identifier, privacy: .public), onDevice \(request.requiresOnDeviceRecognition, privacy: .public)")

        // The result handler arrives on an arbitrary queue, and neither
        // `SFSpeechRecognitionResult` nor `Error` is Sendable. Flatten both into plain
        // value types here, on the callback's own thread, then hop onto the actor with
        // data that can legally cross the boundary.
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
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
            Task { await self.handle(outcome) }
        }

        return chunks
    }

    func feed(_ chunk: AudioChunk) async {
        request?.append(chunk.buffer)
    }

    func finish() async {
        request?.endAudio()
        // The final result (isFinal == true) arrives through the result handler after
        // endAudio; give it a moment, then close the stream if the handler hasn't.
        // Without the timeout a recognizer that dies silently would hang endDictation.
        for _ in 0..<40 where chunkContinuation != nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if let continuation = chunkContinuation {
            chunkContinuation = nil
            continuation.finish()
        }
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
    }

    // MARK: - Result handling

    /// A recognizer callback reduced to Sendable values.
    private enum Outcome: Sendable {
        case text(String, isFinal: Bool)
        case failure(domain: String, code: Int, message: String)
    }

    private func handle(_ outcome: Outcome) {
        switch outcome {
        case .text(let text, let isFinal):
            chunkContinuation?.yield(TranscriptionChunk(text: text, isFinal: isFinal))
            if isFinal {
                chunkContinuation?.finish()
                chunkContinuation = nil
            }

        case .failure(let domain, let code, let message):
            // endAudio() surfaces a benign "no speech detected" cancellation on empty
            // recordings; report real failures, close quietly otherwise.
            let benign = domain == "kAFAssistantErrorDomain" && [203, 216, 1110].contains(code)
            if benign {
                chunkContinuation?.finish()
            } else {
                Log.speech.error("SFSpeechRecognizer failed: \(message, privacy: .public)")
                chunkContinuation?.finish(throwing: TranscriptionError.recognitionFailed(message))
            }
            chunkContinuation = nil
        }
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
