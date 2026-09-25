import Foundation
import GRDB

/// A single stored clipboard entry.
///
/// Text-like content is kept inline (`text`, `htmlText`, `rtfData`). Images and
/// screenshots keep only their file paths here; the bytes live on disk under the
/// blob store. `contentHash` is what dedupe compares.
public struct ClipItem: Identifiable, Equatable, Codable, Sendable {
    public var id: Int64?
    public var kind: ClipKind
    /// Plain-text representation used for previews and full-text search.
    public var text: String?
    /// Short snippet (bounded length) for list rows.
    public var preview: String?
    /// Stable hash of the canonical content, used to collapse duplicates.
    public var contentHash: String
    public var isFavorite: Bool
    public var createdAt: Date
    /// Bumped whenever an identical copy is seen again, floating it to the top.
    public var updatedAt: Date
    /// Approximate byte footprint (inline text + on-disk blobs), for retention.
    public var byteSize: Int

    // Rich-text fidelity (kept inline; usually small).
    public var rtfData: Data?
    public var htmlText: String?

    // Binary payloads live on disk; paths are relative to the blob root.
    public var imagePath: String?
    public var thumbnailPath: String?
    public var pixelWidth: Int?
    public var pixelHeight: Int?

    // File references (JSON-encoded array of paths).
    public var fileURLsJSON: String?

    // Best-effort provenance.
    public var sourceAppBundleID: String?
    public var sourceAppName: String?

    public init(
        id: Int64? = nil,
        kind: ClipKind,
        text: String? = nil,
        preview: String? = nil,
        contentHash: String,
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        byteSize: Int = 0,
        rtfData: Data? = nil,
        htmlText: String? = nil,
        imagePath: String? = nil,
        thumbnailPath: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        fileURLsJSON: String? = nil,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.preview = preview
        self.contentHash = contentHash
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.byteSize = byteSize
        self.rtfData = rtfData
        self.htmlText = htmlText
        self.imagePath = imagePath
        self.thumbnailPath = thumbnailPath
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fileURLsJSON = fileURLsJSON
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
    }

    /// Decoded list of file paths for `.file` items.
    public var fileURLs: [String] {
        guard let json = fileURLsJSON, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

// MARK: - GRDB persistence

extension ClipKind: DatabaseValueConvertible {}

extension ClipItem: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "clip"

    public enum Columns {
        public static let id = Column("id")
        public static let kind = Column("kind")
        public static let text = Column("text")
        public static let preview = Column("preview")
        public static let contentHash = Column("contentHash")
        public static let isFavorite = Column("isFavorite")
        public static let createdAt = Column("createdAt")
        public static let updatedAt = Column("updatedAt")
        public static let byteSize = Column("byteSize")
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
