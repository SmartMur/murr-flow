import AppKit
import Foundation

/// Launch-time environment checks that decide whether the app can work at all.
///
/// Both problems here are invisible from inside the app if you don't look for them:
/// a second copy silently steals the hotkey, and a translocated copy can never hold
/// an Accessibility grant. Each cost a full debugging session in the field.
@MainActor
enum Startup {

    // MARK: - Single instance

    /// True when another copy of Murr-flow is already running.
    ///
    /// Two instances each install a `CGEventTap` for the same key. Both fire on every
    /// press, so the mic opens twice, two HUDs appear, and the transcript is injected
    /// twice — or the second tap wins and the copy you're looking at appears dead.
    static var anotherInstanceIsRunning: Bool {
        let mine = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == Bundle.main.bundleIdentifier
                && app.processIdentifier != mine
        }
    }

    /// Brings the existing copy forward and terminates this one.
    static func yieldToExistingInstance() {
        Log.app.error("another Murr-flow instance is already running — terminating this copy")
        let mine = ProcessInfo.processInfo.processIdentifier
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != mine }?
            .activate(options: [])
        NSApp.terminate(nil)
    }

    // MARK: - App Translocation

    /// True when macOS is running this app from a randomized read-only copy.
    ///
    /// Gatekeeper translocates a quarantined app — one opened straight from a .dmg or
    /// still carrying `com.apple.quarantine` — into
    /// `/private/var/folders/.../AppTranslocation/<uuid>/d/`. The path changes on every
    /// launch, and TCC keys the Accessibility grant to the path, so the grant can never
    /// stick: the hotkey tap fails forever no matter how many times the user toggles
    /// the switch in System Settings.
    static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    /// Explains the translocation dead end and offers the one fix that works.
    ///
    /// Deliberately modal and blocking: the alternative is the app appearing to launch
    /// fine and then ignoring every key press, which is indistinguishable from a bug.
    static func warnAboutTranslocation() {
        Log.app.error("running translocated from \(Bundle.main.bundlePath, privacy: .public) — Accessibility cannot persist")

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Move Murr-flow to Applications"
        alert.informativeText = """
            Murr-flow is running from a temporary read-only copy, which macOS creates \
            for apps opened directly from a disk image or Downloads folder.

            In this state macOS will not remember the Accessibility permission, so the \
            push-to-talk key can never work — no matter how many times you grant it.

            Quit Murr-flow, drag it to your Applications folder, then run:

                xattr -dr com.apple.quarantine /Applications/Murr-flow.app

            and open it from Applications.
            """
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Continue Anyway")

        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }
}
