import Foundation
import Testing

@testable import MurrFlowTranscript

/// Regression cover for issue #9: a 37.9s hold pasted 56 characters.
///
/// Every test here is a case the `Speech` framework will not reproduce on demand — a
/// pause, a sixty-second task ceiling, a late callback — which is why the logic sits in a
/// value type instead of inside the engine.
@Suite("Transcript segment assembly")
struct TranscriptSessionTests {
    /// Drives a session through a list of events and returns everything it asked for.
    private func run(_ events: [TranscriptSession.Event]) -> (TranscriptSession, [TranscriptSession.Action]) {
        var session = TranscriptSession()
        var actions = session.start()
        for event in events { actions += session.handle(event) }
        return (session, actions)
    }

    private func emitted(_ actions: [TranscriptSession.Action]) -> [String] {
        actions.compactMap { if case .emit(let text) = $0 { text } else { nil } }
    }

    private func completion(_ actions: [TranscriptSession.Action]) -> String? {
        actions.compactMap { if case .complete(let text) = $0 { text } else { nil } }.last
    }

    private func opened(_ actions: [TranscriptSession.Action]) -> [Int] {
        actions.compactMap { if case .openSegment(let index) = $0 { index } else { nil } }
    }

    private func closed(_ actions: [TranscriptSession.Action]) -> [Int] {
        actions.compactMap { if case .closeSegment(let index) = $0 { index } else { nil } }
    }

    @Test("opens a first segment to receive audio")
    func startsOneSegment() {
        var session = TranscriptSession()
        #expect(session.start() == [.openSegment(0)])
    }

    // MARK: - The original bug

    @Test("a pause does not end the dictation")
    func pauseOpensAnotherSegment() {
        let (session, actions) = run([
            .revised(segment: 0, text: "the quick brown"),
            .finalized(segment: 0, text: "The quick brown fox."),
        ])

        // The whole of issue #9: isFinal at a natural pause used to close the stream.
        #expect(!session.isFinished)
        #expect(completion(actions) == nil)
        #expect(opened(actions) == [0, 1])
    }

    @Test("speech after a pause is kept, not discarded")
    func accumulatesAcrossPauses() {
        let (session, actions) = run([
            .finalized(segment: 0, text: "The quick brown fox."),
            .finalized(segment: 1, text: "Jumps over the lazy dog."),
            .revised(segment: 2, text: "And then"),
            .finishRequested,
            .finalized(segment: 2, text: "And then it stopped."),
        ])

        #expect(session.isFinished)
        #expect(completion(actions) == "The quick brown fox. Jumps over the lazy dog. And then it stopped.")
    }

    @Test("a three-minute hold with many pauses keeps every segment")
    func longHoldKeepsEverything() {
        var session = TranscriptSession()
        var actions = session.start()
        for index in 0..<40 {
            actions += session.handle(.finalized(segment: index, text: "sentence\(index)"))
        }
        actions += session.handle(.finishRequested)
        // The last final opened a successor that never heard anything. The engine
        // abandons it rather than waiting on a request with no audio in it.
        actions += session.handle(.abandoned(segment: 40))

        let expected = (0..<40).map { "sentence\($0)" }.joined(separator: " ")
        #expect(session.isFinished)
        #expect(completion(actions) == expected)
    }

    // MARK: - Task rotation

    @Test("rotation closes the old task and opens a new one")
    func rotationSwapsSegments() {
        let (session, actions) = run([
            .revised(segment: 0, text: "a long uninterrupted sentence"),
            .rotationDue,
        ])

        #expect(closed(actions) == [0])
        #expect(opened(actions) == [0, 1])
        #expect(!session.isFinished)
    }

    @Test("audio after a rotation lands in the new segment")
    func rotationRoutesLaterAudio() {
        let (session, actions) = run([
            .revised(segment: 0, text: "first half"),
            .rotationDue,
            .revised(segment: 1, text: "second half"),
            .finalized(segment: 0, text: "First half,"),
            .finishRequested,
            .finalized(segment: 1, text: "second half."),
        ])

        #expect(session.isFinished)
        #expect(completion(actions) == "First half, second half.")
    }

    @Test("a rotated-away segment finalizing late does not reorder the transcript")
    func lateFinalKeepsOrder() {
        // The outgoing task reports *after* the incoming one has already produced text.
        let (session, actions) = run([
            .rotationDue,
            .finishRequested,
            .finalized(segment: 1, text: "second."),
            .finalized(segment: 0, text: "First,"),
        ])

        #expect(session.isFinished)
        #expect(completion(actions) == "First, second.")
    }

    @Test("finishing waits for a rotated segment that has not reported")
    func finishWaitsOnPendingSegment() {
        var session = TranscriptSession()
        _ = session.start()
        _ = session.handle(.rotationDue)

        let atFinish = session.handle(.finishRequested)
        _ = session.handle(.finalized(segment: 1, text: "second."))
        #expect(!session.isFinished)
        #expect(completion(atFinish) == nil)

        let actions = session.handle(.finalized(segment: 0, text: "First,"))
        #expect(session.isFinished)
        #expect(completion(actions) == "First, second.")
    }

    @Test("rotation is ignored once the user has let go")
    func noRotationWhileFinishing() {
        var session = TranscriptSession()
        _ = session.start()
        _ = session.handle(.finishRequested)
        #expect(session.handle(.rotationDue).isEmpty)
    }

    // MARK: - Ending the hold

    @Test("releasing the key closes the open segment and completes on its final")
    func finishClosesOpenSegment() {
        var session = TranscriptSession()
        _ = session.start()
        _ = session.handle(.revised(segment: 0, text: "hello"))

        let atFinish = session.handle(.finishRequested)
        #expect(closed(atFinish) == [0])
        #expect(!session.isFinished)

        let actions = session.handle(.finalized(segment: 0, text: "Hello."))
        #expect(session.isFinished)
        #expect(completion(actions) == "Hello.")
    }

    @Test("a silent hold completes with empty text rather than hanging")
    func emptyHoldCompletes() {
        var session = TranscriptSession()
        _ = session.start()
        _ = session.handle(.finishRequested)
        let actions = session.handle(.finalized(segment: 0, text: ""))

        #expect(session.isFinished)
        #expect(completion(actions) == "")
    }

    @Test("a segment that never reports is abandoned rather than blocking the paste")
    func abandonedSegmentUnblocksCompletion() {
        var session = TranscriptSession()
        _ = session.start()
        _ = session.handle(.rotationDue)
        _ = session.handle(.finishRequested)
        _ = session.handle(.finalized(segment: 1, text: "what survived."))
        #expect(!session.isFinished)

        let actions = session.handle(.abandoned(segment: 0))
        #expect(session.isFinished)
        #expect(completion(actions) == "what survived.")
    }

    @Test("forcing completion keeps the text heard so far")
    func forceCompleteKeepsHeardText() {
        var session = TranscriptSession()
        _ = session.start()
        _ = session.handle(.revised(segment: 0, text: "a minute of speech"))

        // A recognizer that dies at the ceiling has still heard a minute. Throwing that
        // away is the failure mode this whole change exists to remove.
        let actions = session.forceComplete()
        #expect(session.isFinished)
        #expect(completion(actions) == "a minute of speech")
    }

    @Test("nothing is emitted after completion")
    func completionIsTerminal() {
        var session = TranscriptSession()
        _ = session.start()
        _ = session.handle(.finishRequested)
        _ = session.handle(.finalized(segment: 0, text: "done."))

        #expect(session.handle(.revised(segment: 0, text: "late")).isEmpty)
        #expect(session.forceComplete().isEmpty)
    }

    // MARK: - Rendering

    @Test("a stale revision does not un-commit settled text")
    func staleRevisionIgnored() {
        var session = TranscriptSession()
        _ = session.start()
        _ = session.handle(.finalized(segment: 0, text: "Committed."))
        _ = session.handle(.revised(segment: 0, text: "commit"))

        #expect(session.rendered == "Committed.")
    }

    @Test("live text spans committed segments and the current guess")
    func rendersCommittedPlusPartial() {
        var session = TranscriptSession()
        _ = session.start()
        _ = session.handle(.finalized(segment: 0, text: "First sentence."))
        let actions = session.handle(.revised(segment: 1, text: "second one in progress"))

        #expect(emitted(actions).last == "First sentence. second one in progress")
    }

    @Test("an empty segment does not leave a gap in the text")
    func emptySegmentsAreNotJoined() {
        var session = TranscriptSession()
        _ = session.start()
        _ = session.handle(.finalized(segment: 0, text: "Before."))
        _ = session.handle(.finalized(segment: 1, text: ""))
        _ = session.handle(.finalized(segment: 2, text: "After."))

        #expect(session.rendered == "Before. After.")
    }

    @Test("a result for a segment that was never opened is ignored")
    func unknownSegmentIgnored() {
        var session = TranscriptSession()
        _ = session.start()
        #expect(session.handle(.finalized(segment: 7, text: "nowhere")).isEmpty)
        #expect(session.rendered == "")
    }
}
