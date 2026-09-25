import Foundation

/// A global hotkey, expressed with Carbon virtual key codes so the core stays
/// AppKit-free. The app maps these to `RegisterEventHotKey`.
public struct HotKeyConfig: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var isEnabled: Bool

    public init(keyCode: UInt32, modifiers: UInt32, isEnabled: Bool = true) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isEnabled = isEnabled
    }

    /// Default ⌥⌘V. keyCode 9 = ANSI "V"; modifiers = cmdKey (0x100) | optionKey (0x800).
    public static let defaultHotKey = HotKeyConfig(keyCode: 9, modifiers: 0x100 | 0x800, isEnabled: true)
}

public enum ExportSchedule: String, Codable, CaseIterable, Sendable {
    case off
    case daily
    case weekly
}

public enum ExportTargetKind: String, Codable, CaseIterable, Sendable {
    /// Copy the archive into a folder. Point it at a Google Drive / iCloud synced
    /// folder to get off-machine backups with no OAuth at all.
    case localFolder
    /// Upload the archive to the user's own Google Drive via OAuth.
    case googleDrive
    /// Email the archive to the user's own Gmail via OAuth.
    case gmail
}

/// Configuration for a single export destination.
public struct ExportTargetConfig: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: ExportTargetKind
    public var isEnabled: Bool

    // Local folder target.
    public var localFolderPath: String?

    // Google targets use the user's OWN OAuth client (never bundled).
    public var googleClientID: String?
    public var googleClientSecret: String?
    /// Where a Gmail export is sent (defaults to the authenticated account).
    public var gmailRecipient: String?

    public init(
        id: UUID = UUID(),
        kind: ExportTargetKind,
        isEnabled: Bool = false,
        localFolderPath: String? = nil,
        googleClientID: String? = nil,
        googleClientSecret: String? = nil,
        gmailRecipient: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.isEnabled = isEnabled
        self.localFolderPath = localFolderPath
        self.googleClientID = googleClientID
        self.googleClientSecret = googleClientSecret
        self.gmailRecipient = gmailRecipient
    }
}

/// The opt-in, OFF-by-default cloud/export configuration.
public struct ExportSettings: Codable, Equatable, Sendable {
    /// Master switch. When false, nothing is ever exported.
    public var isEnabled: Bool
    public var schedule: ExportSchedule
    public var targets: [ExportTargetConfig]
    /// Include image/screenshot blobs in the archive (larger exports).
    public var includeBlobs: Bool
    /// Timestamp of the last successful run, for scheduling.
    public var lastRunAt: Date?

    public init(
        isEnabled: Bool = false,
        schedule: ExportSchedule = .off,
        targets: [ExportTargetConfig] = [],
        includeBlobs: Bool = true,
        lastRunAt: Date? = nil
    ) {
        self.isEnabled = isEnabled
        self.schedule = schedule
        self.targets = targets
        self.includeBlobs = includeBlobs
        self.lastRunAt = lastRunAt
    }

    public static let disabled = ExportSettings()
}

/// The full, persisted application configuration.
public struct AppSettings: Codable, Equatable, Sendable {
    /// How often to poll the pasteboard, in milliseconds.
    public var pollingIntervalMilliseconds: Int
    public var retention: RetentionPolicy
    /// Bundle identifiers whose copies are never recorded.
    public var excludedBundleIDs: [String]
    /// When true, capture is suspended.
    public var isPaused: Bool
    public var launchAtLogin: Bool
    /// Number of items shown in the pinned top strip.
    public var topStripCount: Int
    public var hotKey: HotKeyConfig
    public var export: ExportSettings
    /// Paste into the previous app automatically after selecting an item.
    public var pasteOnSelect: Bool
    /// Preferred appearance: nil = follow system.
    public var forcedDarkMode: Bool?

    public init(
        pollingIntervalMilliseconds: Int = 300,
        retention: RetentionPolicy = .standard,
        excludedBundleIDs: [String] = [],
        isPaused: Bool = false,
        launchAtLogin: Bool = false,
        topStripCount: Int = 10,
        hotKey: HotKeyConfig = .defaultHotKey,
        export: ExportSettings = .disabled,
        pasteOnSelect: Bool = true,
        forcedDarkMode: Bool? = nil
    ) {
        self.pollingIntervalMilliseconds = pollingIntervalMilliseconds
        self.retention = retention
        self.excludedBundleIDs = excludedBundleIDs
        self.isPaused = isPaused
        self.launchAtLogin = launchAtLogin
        self.topStripCount = topStripCount
        self.hotKey = hotKey
        self.export = export
        self.pasteOnSelect = pasteOnSelect
        self.forcedDarkMode = forcedDarkMode
    }

    public static let `default` = AppSettings()
}
