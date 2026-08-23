import Foundation

/// Where the app keeps the dictionary and the run log, and the one-time move off the old name.
///
/// The directory was called `MurmurYouTube` before the rename to Murr-flow. Anyone upgrading
/// across that boundary already has a dictionary they have hand-tuned, so the first access
/// moves the old directory into place rather than silently starting from empty.
enum AppSupport {
    private static let directoryName = "MurrFlow"
    private static let legacyDirectoryName = "MurmurYouTube"

    /// Resolved once per launch: the migration only ever needs to run on the first access.
    static let directory: URL = {
        let files = FileManager.default
        let root = files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = root.appendingPathComponent(directoryName, isDirectory: true)
        let legacy = root.appendingPathComponent(legacyDirectoryName, isDirectory: true)

        // Only migrate into a clean slot. If both exist, the new one already won.
        if !files.fileExists(atPath: base.path), files.fileExists(atPath: legacy.path) {
            do {
                try files.moveItem(at: legacy, to: base)
                Log.app.info("migrated app support from \(legacyDirectoryName, privacy: .public)")
            } catch {
                Log.app.error("app support migration failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        try? files.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()
}
