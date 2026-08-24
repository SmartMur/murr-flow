import Foundation

/// Assembles one dictation out of the several recognition segments it actually arrives in.
///
/// `SFSpeechRecognizer` does not hand back one transcript per key-hold. It finalizes an
/// *utterance* whenever it decides speech has paused, and a recognition task stops outright
/// at roughly a minute regardless. A long hold is therefore a sequence of segments: some
/// ended by the speaker pausing, some ended by us rotating the task before it hits that
/// ceiling. Treating the first `isFinal` as the end of the dictation is what made a 38s hold
/// paste 56 characters.
///
/// This type owns all of that bookkeeping — segment order, which segments are still expected
/// to report, and when the dictation is genuinely over — so the engine wrapped around it
/// holds nothing but `Speech` objects and a timer.
///
/// It deliberately does not import `Speech`. That is what makes the behaviour testable:
/// the framework will not produce a sixty-second pause, a late final, or an out-of-order
/// callback on demand, and those are exactly the cases that were broken.
public struct TranscriptSession: Sendable, Equatable {
    /// Something the recognizer, the clock, or the user did.
    public enum Event: Sendable, Equatable {
        /// A revised, non-final guess at the text of one segment.
        case revised(segment: Int, text: String)
        /// The recognizer has committed a segment and will say no more about it.
        case finalized(segment: Int, text: String)
        /// The open segment is approaching the recognition-task ceiling.
        case rotationDue
        /// The user let go of the key.
        case finishRequested
        /// A segment we were still waiting on will never report.
        case abandoned(segment: Int)
    }

    /// Something the engine must do about it. Order within the array is significant.
    public enum Action: Sendable, Equatable {
        /// Show this text. Always the full transcript, never a delta.
        case emit(String)
        /// Create a recognition request and task tagged with this index, and route
        /// subsequent audio to it.
        case openSegment(Int)
        /// Call `endAudio()` on this segment's request. Its final result is still expected.
        case closeSegment(Int)
        /// The dictation is over and this is the whole of it.
        case complete(String)
    }

    private var texts: [String] = []
    private var committed: Set<Int> = []
    /// The segment currently receiving audio, if any.
    private var open: Int?
    /// Segments that have been closed but have not yet reported a final result.
    private var pending: Set<Int> = []
    private var finishing = false
    private var finished = false

    public init() {}

    /// Opens the first segment. The engine starts its first recognition task from this.
    public mutating func start() -> [Action] {
        guard texts.isEmpty else { return [] }
        let index = appendSegment()
        open = index
        return [.openSegment(index)]
    }

    public mutating func handle(_ event: Event) -> [Action] {
        guard !finished else { return [] }

        switch event {
        case .revised(let index, let text):
            // A revision to a committed segment is a stale callback overtaking the final
            // that closed it. Dropping it stops settled text flickering back to a guess.
            guard texts.indices.contains(index), !committed.contains(index) else { return [] }
            texts[index] = text
            return [.emit(rendered)]

        case .finalized(let index, let text):
            guard texts.indices.contains(index), !committed.contains(index) else { return [] }
            texts[index] = text
            committed.insert(index)
            pending.remove(index)

            var actions: [Action] = [.emit(rendered)]

            // The recognizer ended the *open* segment on its own — a natural pause. Unless
            // the user has already let go, the hold is still running, so a fresh task has
            // to take over or everything said after the pause is lost.
            if open == index {
                open = nil
                if !finishing {
                    let next = appendSegment()
                    open = next
                    actions.append(.openSegment(next))
                }
            }

            if let completion = completionIfDone() { actions.append(completion) }
            return actions

        case .rotationDue:
            // Rotating while finishing would open a task that can never receive audio.
            guard !finishing, let current = open else { return [] }
            pending.insert(current)
            let next = appendSegment()
            open = next
            return [.closeSegment(current), .openSegment(next)]

        case .finishRequested:
            guard !finishing else { return [] }
            finishing = true
            var actions: [Action] = []
            if let current = open {
                pending.insert(current)
                open = nil
                actions.append(.closeSegment(current))
            }
            if let completion = completionIfDone() { actions.append(completion) }
            return actions

        case .abandoned(let index):
            guard pending.remove(index) != nil else { return [] }
            if let completion = completionIfDone() { return [completion] }
            return []
        }
    }

    /// The full transcript as it currently stands, committed segments and live guess alike.
    ///
    /// Empty segments are dropped rather than joined: a rotation that lands in silence,
    /// or a pause the recognizer resolves to nothing, would otherwise show up as a run of
    /// spaces in the middle of the sentence.
    public var rendered: String {
        texts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Whether the session has emitted its `.complete` action.
    public var isFinished: Bool { finished }

    /// Closes the session immediately, whatever is still outstanding.
    ///
    /// The engine calls this when a recognizer stops answering. Returning the text gathered
    /// so far is the entire point: a task that dies at 60s has still heard a minute of
    /// speech, and throwing that away is the bug this type exists to fix.
    public mutating func forceComplete() -> [Action] {
        guard !finished else { return [] }
        finished = true
        return [.complete(rendered)]
    }

    private mutating func appendSegment() -> Int {
        texts.append("")
        return texts.count - 1
    }

    private mutating func completionIfDone() -> Action? {
        guard finishing, open == nil, pending.isEmpty, !finished else { return nil }
        finished = true
        return .complete(rendered)
    }
}
