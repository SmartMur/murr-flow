import XCTest
@testable import MurrFlowOnboarding

/// A world the test controls completely, so every permission combination is reachable
/// without touching TCC.
@MainActor
private final class StubEnvironment: OnboardingEnvironment {
    var hasAccessibility = true
    var hasMicrophone = true
    var hasSpeechRecognition = true
    var isTranslocated = false
}

@MainActor
final class OnboardingModelTests: XCTestCase {

    private func makeModel(
        configure: (StubEnvironment) -> Void = { _ in }
    ) -> (OnboardingModel, StubEnvironment, () -> Int) {
        let environment = StubEnvironment()
        configure(environment)
        var completions = 0
        let model = OnboardingModel(environment: environment) { completions += 1 }
        return (model, environment, { completions })
    }

    // MARK: - Ordering

    func testStartsAtWelcome() {
        let (model, _, _) = makeModel()
        XCTAssertEqual(model.step, .welcome)
    }

    func testAdvancesThroughEveryStepInOrder() {
        let (model, _, _) = makeModel()
        XCTAssertEqual(model.step, .welcome)
        for expected in [OnboardingStep.permissions, .microphone, .shortcut, .tryIt, .done] {
            XCTAssertTrue(model.advance(), "should advance to \(expected)")
            XCTAssertEqual(model.step, expected)
        }
    }

    func testCannotAdvancePastDone() {
        let (model, _, _) = makeModel()
        while model.step != .done { XCTAssertTrue(model.advance()) }
        XCTAssertFalse(model.advance())
        XCTAssertEqual(model.step, .done)
    }

    func testGoBackWalksBackwardsButNotBeforeWelcome() {
        let (model, _, _) = makeModel()
        model.advance()
        XCTAssertEqual(model.step, .permissions)
        XCTAssertTrue(model.goBack())
        XCTAssertEqual(model.step, .welcome)
        XCTAssertFalse(model.goBack(), "welcome is the first step")
    }

    func testCannotGoBackFromDone() {
        let (model, _, _) = makeModel()
        while model.step != .done { model.advance() }
        XCTAssertFalse(model.goBack())
    }

    // MARK: - Permission gating

    /// The bug this whole flow exists to prevent: setup completing while a permission the
    /// app cannot work without is still missing.
    func testPermissionsStepBlocksWhenAccessibilityMissing() {
        let (model, environment, _) = makeModel { $0.hasAccessibility = false }
        model.advance()
        XCTAssertEqual(model.step, .permissions)
        XCTAssertFalse(model.canAdvance)
        XCTAssertFalse(model.advance())
        XCTAssertEqual(model.step, .permissions, "must not slip past a missing permission")

        environment.hasAccessibility = true
        XCTAssertTrue(model.canAdvance)
        XCTAssertTrue(model.advance())
        XCTAssertEqual(model.step, .microphone)
    }

    func testPermissionsStepBlocksWhenMicrophoneMissing() {
        let (model, _, _) = makeModel { $0.hasMicrophone = false }
        model.advance()
        XCTAssertFalse(model.advance())
        XCTAssertEqual(model.step, .permissions)
    }

    /// Speech Recognition is a separate TCC grant from the microphone, and the legacy
    /// engine on Intel Macs cannot run without it.
    func testPermissionsStepBlocksWhenSpeechRecognitionMissing() {
        let (model, _, _) = makeModel { $0.hasSpeechRecognition = false }
        model.advance()
        XCTAssertFalse(model.advance())
        XCTAssertEqual(model.step, .permissions)
    }

    func testBlockedReasonNamesEveryMissingPermission() {
        let (model, _, _) = makeModel {
            $0.hasAccessibility = false
            $0.hasSpeechRecognition = false
        }
        model.advance()
        let reason = try? XCTUnwrap(model.blockedReason)
        XCTAssertTrue(reason??.contains("Accessibility") == true)
        XCTAssertTrue(reason??.contains("Speech Recognition") == true)
        XCTAssertFalse(reason??.contains("Microphone") == true, "granted permissions must not be listed")
    }

    func testBlockedReasonIsNilWhenNothingBlocks() {
        let (model, _, _) = makeModel()
        model.advance()
        XCTAssertNil(model.blockedReason)
    }

    /// A translocated app can never hold a permission grant, so no amount of toggling
    /// will satisfy this step. The flow must say so rather than looping forever.
    func testTranslocationBlocksEvenWithEveryPermissionGranted() {
        let (model, _, _) = makeModel { $0.isTranslocated = true }
        model.advance()
        XCTAssertEqual(model.step, .permissions)
        XCTAssertTrue(model.permissionsSatisfied, "the grants themselves are present")
        XCTAssertFalse(model.canAdvance, "but they cannot persist while translocated")
        XCTAssertEqual(
            model.blockedReason,
            "Move Murr-flow to your Applications folder first — macOS won't remember these permissions otherwise."
        )
    }

    /// Losing an input device must not trap the user on a screen with no way forward.
    func testMicrophoneStepIsNotBlocking() {
        let (model, _, _) = makeModel()
        model.advance()
        model.advance()
        XCTAssertEqual(model.step, .microphone)
        XCTAssertTrue(model.canAdvance)
    }

    // MARK: - Completion

    func testCompletionFiresExactlyOnceOnReachingDone() {
        let (model, _, completions) = makeModel()
        while model.step != .done { model.advance() }
        XCTAssertEqual(completions(), 1)
        model.advance()
        XCTAssertEqual(completions(), 1, "already-complete flow must not re-fire")
    }

    func testCompletionDoesNotFireWhileBlocked() {
        let (model, _, completions) = makeModel { $0.hasAccessibility = false }
        for _ in 0..<10 { model.advance() }
        XCTAssertEqual(completions(), 0)
        XCTAssertEqual(model.step, .permissions)
    }

    // MARK: - Progress

    func testProgressRunsFromZeroToOne() {
        let (model, _, _) = makeModel()
        XCTAssertEqual(model.progress, 0, accuracy: 0.001)
        while model.step != .done { model.advance() }
        XCTAssertEqual(model.progress, 1, accuracy: 0.001)
    }

    func testEveryStepHasCopy() {
        for step in OnboardingStep.allCases {
            XCTAssertFalse(step.title.isEmpty, "\(step) needs a title")
            XCTAssertFalse(step.subtitle.isEmpty, "\(step) needs a subtitle")
        }
    }
}
