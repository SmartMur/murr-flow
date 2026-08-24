import Foundation

/// Detects push-to-talk keys already claimed by another dictation app.
///
/// This exists because of a real, silent failure: Wispr Flow binds push-to-talk to the
/// `fn` key (virtual keycode 63), which was previously Murr-flow's default. Both apps install a
/// `CGEventTap` for the same key, both fire on every press, and the user sees two HUDs,
/// two recordings, or — depending on tap order — nothing useful at all. Nothing in either
/// app reports the clash, so it reads as "Murr-flow is broken".
///
/// Detection is config-file based rather than by probing the OS: macOS has no API to ask
/// "who else has an event tap on this key", so the only honest source is the other app's
/// own settings.
public struct ShortcutConflict: Equatable, Sendable {
    /// The app that already claims the key, as a user would name it.
    public let appName: String
    /// Human-readable name of the contested key, e.g. "fn".
    public let keyName: String

    public init(appName: String, keyName: String) {
        self.appName = appName
        self.keyName = keyName
    }

    public var message: String {
        "\(appName) already uses \(keyName) for dictation. Holding it would trigger both apps — pick a different key."
    }
}

/// A rival dictation app whose keybindings can be read from disk.
public struct RivalApp: Sendable {
    public let name: String
    /// Path to its config, relative to the user's home directory.
    public let configPath: String
    /// Pulls the claimed virtual keycodes out of that config's contents.
    public let parse: @Sendable (Data) -> Set<Int>

    public init(name: String, configPath: String, parse: @escaping @Sendable (Data) -> Set<Int>) {
        self.name = name
        self.configPath = configPath
        self.parse = parse
    }

    /// Wispr Flow stores keybindings as `prefs.cache.splitKeybinds`, each entry a
    /// `{"shortcut": [<keycodes>], "value": "<action>"}`. Only single-key bindings matter:
    /// a combo like `[59, 63]` (control+fn) does not fire on a bare `fn` hold, so treating
    /// it as a conflict would warn about a key that actually works fine.
    public static let wisprFlow = RivalApp(
        name: "Wispr Flow",
        configPath: "Library/Application Support/Wispr Flow/config.json"
    ) { data in
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let prefs = root["prefs"] as? [String: Any],
            let cache = prefs["cache"] as? [String: Any],
            let binds = cache["splitKeybinds"] as? [[String: Any]]
        else { return [] }

        var claimed: Set<Int> = []
        for bind in binds {
            guard let shortcut = bind["shortcut"] as? [Int], shortcut.count == 1 else { continue }
            claimed.insert(shortcut[0])
        }
        return claimed
    }

    public static let all: [RivalApp] = [.wisprFlow]
}

/// Checks a candidate key against every rival app's configuration.
public enum ShortcutConflictChecker {

    /// - Parameters:
    ///   - keyCode: the virtual keycode Murr-flow would tap.
    ///   - keyName: display name for that key, used in the warning.
    ///   - home: home directory to resolve config paths against; injectable for tests.
    ///   - rivals: apps to check. Defaults to every known rival.
    /// - Returns: the first conflict found, or `nil` when the key is free.
    public static func check(
        keyCode: Int,
        keyName: String,
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        rivals: [RivalApp] = RivalApp.all
    ) -> ShortcutConflict? {
        for rival in rivals {
            let url = home.appending(path: rival.configPath)
            // A rival that isn't installed is not a conflict, so an unreadable config is
            // silently fine — never a reason to block the user.
            guard let data = try? Data(contentsOf: url) else { continue }
            if rival.parse(data).contains(keyCode) {
                return ShortcutConflict(appName: rival.name, keyName: keyName)
            }
        }
        return nil
    }
}
