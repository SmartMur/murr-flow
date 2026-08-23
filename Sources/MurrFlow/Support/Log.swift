import OSLog

enum Log {
    /// Matches `CFBundleIdentifier`, so `log show --predicate 'subsystem == "…"'` finds us.
    private static let subsystem = "com.smartmur.murrflow"

    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let speech = Logger(subsystem: subsystem, category: "speech")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let inject = Logger(subsystem: subsystem, category: "inject")
    static let app = Logger(subsystem: subsystem, category: "app")
}
