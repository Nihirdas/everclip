import Foundation

public enum ExportError: LocalizedError {
    case notConfigured(String)
    case archiveFailed(String)
    case transportFailed(String)
    case authFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let m): return "Export target not configured: \(m)"
        case .archiveFailed(let m): return "Could not build the archive: \(m)"
        case .transportFailed(let m): return "Export transport failed: \(m)"
        case .authFailed(let m): return "Authorization failed: \(m)"
        }
    }
}

/// One row in an export manifest — a portable, JSON-friendly view of a `ClipItem`.
public struct ArchiveManifestItem: Codable, Equatable, Sendable {
    public var id: Int64?
    public var kind: String
    public var text: String?
    public var preview: String?
    public var isFavorite: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var sourceAppName: String?
    public var fileURLs: [String]
    /// Relative path to the copied blob inside the archive, if included.
    public var blobPath: String?

    public init(from item: ClipItem, blobPath: String?) {
        self.id = item.id
        self.kind = item.kind.rawValue
        self.text = item.text
        self.preview = item.preview
        self.isFavorite = item.isFavorite
        self.createdAt = item.createdAt
        self.updatedAt = item.updatedAt
        self.pixelWidth = item.pixelWidth
        self.pixelHeight = item.pixelHeight
        self.sourceAppName = item.sourceAppName
        self.fileURLs = item.fileURLs
        self.blobPath = blobPath
    }
}

public struct ArchiveManifest: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var application: String
    public var createdAt: Date
    public var itemCount: Int
    public var items: [ArchiveManifestItem]

    public init(createdAt: Date, items: [ArchiveManifestItem]) {
        self.formatVersion = 1
        self.application = "EverClip"
        self.createdAt = createdAt
        self.itemCount = items.count
        self.items = items
    }
}

/// A built, on-disk archive ready to hand to an `ExportTarget`.
public struct ClipArchive: Sendable {
    public let directoryURL: URL
    /// A zipped copy of `directoryURL`, when the builder was asked to make one.
    public let zipURL: URL?
    public let itemCount: Int
    public let createdAt: Date

    public var preferredFileURL: URL { zipURL ?? directoryURL }
    public var suggestedName: String { preferredFileURL.lastPathComponent }
}
