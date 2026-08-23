import AppKit
import SwiftUI

@main
struct MurrFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Single main window — no WindowGroup, because ⌘N opening a second copy is wrong.
        Window("Murr-flow", id: "main") {
            MainWindow(controller: delegate.controller)
        }
        .defaultSize(width: 860, height: 620)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Reveal Dictionary File") {
                    NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL])
                }
            }
        }

        // Fully qualified to avoid shadowing SwiftUI.Settings.
        SwiftUI.Settings {
            SettingsWindow(controller: delegate.controller)
        }

        // Menu bar entry — always present, never in the Dock while idle.
        MenuBarExtra {
            MenuContent(controller: delegate.controller)
        } label: {
            Image(systemName: delegate.controller.state.isActive
                  ? "waveform.circle.fill" : "waveform")
        }

        // Engine comparison tool — secondary debugging/evaluation window.
        Window("Engine comparison", id: "comparison") {
            ComparisonWindow(controller: delegate.controller)
        }
        .defaultSize(width: 640, height: 560)
        .windowResizability(.contentMinSize)
    }
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()
    private var hud: HUDPanel?
    private var stateObservation: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        hud = HUDPanel(controller: controller)

        if !controller.activate() {
            Permissions.promptForAccessibility()
            retryActivation()
        }

        RunLog.regenerate()

        // Warm Parakeet models in the background so the first hold doesn't stall.
        let willUseParakeet = Settings.shared.compareMode || Settings.shared.engine == .parakeet
        if willUseParakeet, ParakeetModels.isDownloaded {
            Task.detached(priority: .utility) {
                _ = try? await ParakeetModels.shared.manager()
            }
        }

        if UserDefaults.standard.bool(forKey: "comparisonWindowOpen") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                Self.showComparisonWindow()
            }
        }

        observeState()
        startTapHealthCheck()

        Log.app.info("Murr-flow ready — hold \(Settings.shared.pushToTalkKey.displayName) to dictate")
    }

    /// `murrflow://clear` and `murrflow://show` — used by the HTML dashboard and as
    /// a scriptable way to raise the window.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "murrflow" {
            switch url.host {
            case "clear":
                RunLog.clear()
                RunStore.shared.reload()
            case "show":
                Self.showComparisonWindow()
            default:
                break
            }
        }
    }

    static func showComparisonWindow() {
        RunStore.shared.reload()
        if let existing = NSApp.windows.first(where: { $0.title == "Engine comparison" }) {
            existing.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        let isOpen = NSApp.windows.contains { $0.title == "Engine comparison" && $0.isVisible }
        UserDefaults.standard.set(isOpen, forKey: "comparisonWindowOpen")
        controller.deactivate()
    }

    // MARK: - HUD state tracking

    private func observeState() {
        withObservationTracking {
            _ = controller.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.controller.state.isActive {
                    self.hud?.present()
                } else {
                    self.hud?.dismiss()
                }
                self.observeState()
            }
        }
    }

    // MARK: - Accessibility retry loop

    private func retryActivation() {
        Task { @MainActor in
            while !Permissions.hasAccessibility {
                try? await Task.sleep(for: .seconds(1))
            }
            _ = controller.activate()
            Log.app.info("Accessibility granted — hotkey armed")
        }
    }

    // MARK: - CGEvent tap health-check

    /// Unsigned builds can silently lose the CGEvent tap (OS revokes it after sleep/wake
    /// cycles or privacy-policy changes). Every 30 s — outside an active session — we
    /// deactivate and re-arm so a stale tap is always caught before the next push-to-talk.
    private func startTapHealthCheck() {
        Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                // Never interrupt an active dictation.
                guard !controller.state.isActive else { continue }
                // Nothing to verify without Accessibility.
                guard Permissions.hasAccessibility else { continue }

                controller.deactivate()
                if !controller.activate() {
                    Log.app.warning("CGEvent tap health-check failed — tap could not be re-armed")
                }
            }
        }
    }
}

// MARK: - Menu bar content

private struct MenuContent: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    @Environment(\.openWindow) private var openWindow
    @State private var isPreloadingParakeet = false
    @State private var parakeetOnDisk = ParakeetModels.isDownloaded

    private var parakeetStatus: String {
        if isPreloadingParakeet { return "Loading Parakeet models…" }
        return parakeetOnDisk ? "Parakeet models installed ✓" : "Download Parakeet models…"
    }

    private func preloadParakeet() {
        guard !isPreloadingParakeet else { return }
        isPreloadingParakeet = true
        Task {
            do {
                _ = try await ParakeetModels.shared.manager()
                parakeetOnDisk = ParakeetModels.isDownloaded
            } catch {
                Log.speech.error("Parakeet preload failed: \(error.localizedDescription)")
            }
            isPreloadingParakeet = false
        }
    }

    var body: some View {
        Text("Hold \(settings.pushToTalkKey.displayName) to dictate")

        Divider()

        Picker("Push-to-talk key", selection: Binding(
            get: { settings.pushToTalkKey },
            set: { key in
                settings.pushToTalkKey = key
                controller.reloadHotkey()
            }
        )) {
            ForEach(PushToTalkKey.allCases, id: \.self) { key in
                Text(key.displayName).tag(key)
            }
        }

        if ParakeetSupport.isAvailable {
            Toggle("Compare mode (both engines)", isOn: $settings.compareMode)
        }

        if !settings.compareMode {
            Picker("Engine", selection: $settings.engine) {
                ForEach(SpeechEngineChoice.supportedCases, id: \.self) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
        }

        Toggle("Clean up text", isOn: $settings.cleanupEnabled)

        if settings.cleanupEnabled {
            Toggle("Smart cleanup (on-device AI)", isOn: $settings.smartCleanup)
                .disabled(!FoundationModelFormatter.isAvailable)
            if let reason = FoundationModelFormatter.unavailableReason {
                Text(reason).font(.caption)
            }
        }

        Toggle("Sound", isOn: $settings.soundEnabled)

        Divider()

        if ParakeetSupport.isAvailable {
            Button("Show comparison window") {
                RunStore.shared.reload()
                openWindow(id: "comparison")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("d")
        }

        if settings.engine == .parakeet {
            Button(parakeetStatus) { preloadParakeet() }
                .disabled(isPreloadingParakeet || parakeetOnDisk)
        }

        if !Permissions.hasAccessibility {
            Button("Grant Accessibility…") { Permissions.openAccessibilitySettings() }
        }
        if !Permissions.hasMicrophone {
            Button("Grant Microphone…") { Permissions.openMicrophoneSettings() }
        }

        Button("Quit Murr-flow") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
