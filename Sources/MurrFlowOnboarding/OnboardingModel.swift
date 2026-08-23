import Foundation
import Observation

/// The first-run setup flow.
///
/// Every step here exists because its absence cost a real debugging session: the app
/// launched, looked fine, and silently did nothing because a permission was missing, the
/// shortcut collided with another app, or no speech engine existed on the hardware.
/// Onboarding's job is to make each of those visible *before* the user tries to dictate.
///
/// The model is deliberately free of AppKit and SwiftUI so the whole flow — ordering,
/// gating, completion — is testable without launching an app.
enum OnboardingStep: Int, CaseIterable, Sendable, Comparable {
    case welcome
    case permissions
    case microphone
    case shortcut
    case tryIt
    case done

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome to Murr-flow"
        case .permissions: "Three permissions"
        case .microphone: "Test your microphone"
        case .shortcut: "Pick your key"
        case .tryIt: "Try it yourself"
        case .done: "You're all set"
        }
    }

    /// Shown under the title. One sentence, says what this screen is for.
    var subtitle: String {
        switch self {
        case .welcome:
            "Hold a key, talk, release. Your words appear wherever you're typing."
        case .permissions:
            "Murr-flow can't work without these. Each one is checked live."
        case .microphone:
            "Pick the microphone to listen on, and check that it hears you."
        case .shortcut:
            "Choose the key you'll hold to dictate."
        case .tryIt:
            "Hold your key, say something, then let go."
        case .done:
            "Murr-flow lives in your menu bar, ready whenever you are."
        }
    }

    /// Steps the user may not skip past until satisfied.
    ///
    /// `.microphone` is deliberately *not* blocking: a user with no working input device
    /// should still be able to finish setup and fix the hardware later, rather than being
    /// trapped on a screen with no exit.
    var isBlocking: Bool {
        switch self {
        case .permissions: true
        case .welcome, .microphone, .shortcut, .tryIt, .done: false
        }
    }
}

/// What the flow needs to know about the world, so tests can supply it directly.
///
/// A protocol rather than reading `Permissions` statics inline: the whole point is to be
/// able to drive the flow through every permission combination without touching TCC.
@MainActor
protocol OnboardingEnvironment {
    var hasAccessibility: Bool { get }
    var hasMicrophone: Bool { get }
    var hasSpeechRecognition: Bool { get }
    /// True when macOS is running a randomized read-only copy — permissions can never
    /// persist, so setup is pointless until the user moves the app.
    var isTranslocated: Bool { get }
}

/// Drives the first-run flow.
@MainActor
@Observable
final class OnboardingModel {
    private(set) var step: OnboardingStep = .welcome
    private let environment: any OnboardingEnvironment
    private let markComplete: @MainActor () -> Void

    init(
        environment: any OnboardingEnvironment,
        markComplete: @escaping @MainActor () -> Void = { OnboardingState.markComplete() }
    ) {
        self.environment = environment
        self.markComplete = markComplete
    }

    // MARK: - Gating

    /// Whether every permission this app cannot run without has been granted.
    var permissionsSatisfied: Bool {
        environment.hasAccessibility
            && environment.hasMicrophone
            && environment.hasSpeechRecognition
    }

    /// Whether the user may leave the current step.
    ///
    /// Only blocking steps can refuse. A translocated app can never satisfy
    /// `.permissions`, which is intentional — the flow should stall there and tell the
    /// user to move the app rather than march them through a setup that cannot stick.
    var canAdvance: Bool {
        guard step != .done else { return false }
        guard step.isBlocking else { return true }
        return permissionsSatisfied && !environment.isTranslocated
    }

    /// Why the current step won't let the user past. `nil` when it will.
    var blockedReason: String? {
        guard step.isBlocking, !canAdvance else { return nil }
        if environment.isTranslocated {
            return "Move Murr-flow to your Applications folder first — macOS won't remember these permissions otherwise."
        }
        var missing: [String] = []
        if !environment.hasAccessibility { missing.append("Accessibility") }
        if !environment.hasMicrophone { missing.append("Microphone") }
        if !environment.hasSpeechRecognition { missing.append("Speech Recognition") }
        guard !missing.isEmpty else { return nil }
        return "Still needed: " + missing.joined(separator: ", ")
    }

    // MARK: - Navigation

    @discardableResult
    func advance() -> Bool {
        guard canAdvance else { return false }
        let next = OnboardingStep(rawValue: step.rawValue + 1) ?? .done
        step = next
        if next == .done { markComplete() }
        return true
    }

    @discardableResult
    func goBack() -> Bool {
        guard step != .welcome, step != .done else { return false }
        step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
        return true
    }

    /// Fraction complete, for the progress bar. `.done` is 1.
    var progress: Double {
        Double(step.rawValue) / Double(OnboardingStep.done.rawValue)
    }
}

/// Whether first-run setup has been completed, persisted across launches.
@MainActor
enum OnboardingState {
    private static let key = "onboardingCompletedVersion"
    /// Bumped when a future release adds a step existing users must also see.
    static let currentVersion = 1

    static var isComplete: Bool {
        UserDefaults.standard.integer(forKey: key) >= currentVersion
    }

    static func markComplete() {
        UserDefaults.standard.set(currentVersion, forKey: key)
    }

    /// Used by the menu's "Run setup again…" item and by tests.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
