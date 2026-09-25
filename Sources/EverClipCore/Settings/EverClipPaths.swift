import Foundation

/// Canonical on-disk locations. Everything lives under
/// `~/Library/Application Support/EverClip` — no data ever leaves the machine
/// unless the user explicitly enables an export target.
public enum EverClipPaths {
    public static let folderName = "EverClip"

    public static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Directory holding the SQLite database and blob files.
    public static func storeDirectory() throws -> URL {
        try applicationSupportDirectory()
    }

    public static func settingsURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent("settings.json")
    }
}
