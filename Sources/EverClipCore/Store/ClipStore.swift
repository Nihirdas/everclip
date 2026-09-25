import Foundation
import GRDB

/// The result of attempting to store a draft.
public enum StoreOutcome: Equatable, Sendable {
    /// A brand-new item was inserted.
    case inserted(ClipItem)
    /// An identical item already existed; its timestamp was bumped to the top.
    case duplicateBumped(ClipItem)
    /// The draft was empty or otherwise not stored.
    case skipped

    public var item: ClipItem? {
        switch self {
        case .inserted(let i), .duplicateBumped(let i): return i
        case .skipped: return nil
        }
    }
}

/// The searchable, deduplicated, retention-managed history store.
///
/// This type owns all persistence and is the single API the app and the exporters
/// use. It contains no AppKit, so it is fully unit-testable and reusable by a
/// future port.
public final class ClipStore {
    private let dbQueue: DatabaseQueue
    private let blobStore: BlobStore?

    public init(dbQueue: DatabaseQueue, blobStore: BlobStore?) {
        self.dbQueue = dbQueue
        self.blobStore = blobStore
    }

    /// Opens (or creates) a file-backed store rooted at `directory`.
    public convenience init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent(ClipDatabase.fileName)
        let queue = try ClipDatabase.makeQueue(at: dbURL)
        let blobs = try BlobStore(root: directory)
        self.init(dbQueue: queue, blobStore: blobs)
    }

    /// An in-memory store for tests. Pass a `BlobStore` to exercise image paths.
    public static func inMemory(blobStore: BlobStore? = nil) throws -> ClipStore {
        let queue = try ClipDatabase.makeInMemoryQueue()
        return ClipStore(dbQueue: queue, blobStore: blobStore)
    }

    // MARK: - Writing

    /// Stores a draft, collapsing duplicates. Returns what happened.
    @discardableResult
    public func store(_ draft: ClipDraft) throws -> StoreOutcome {
        let hash = ContentHasher.hash(for: draft)

        return try dbQueue.write { db in
            // Duplicate? Bump the existing row to the top and reuse it.
            if var existing = try ClipItem
                .filter(ClipItem.Columns.contentHash == hash)
                .order(ClipItem.Columns.updatedAt.desc)
                .fetchOne(db) {
                existing.updatedAt = Date()
                try existing.update(db)
                return .duplicateBumped(existing)
            }

            // New item. Persist any blob first so the row can reference it.
            var stored: StoredBlob?
            if draft.kind.isBinary, let data = draft.imageData, let blobStore {
                stored = try blobStore.writeImage(
                    data,
                    fileExtension: draft.imageFileExtension ?? "png",
                    hash: hash
                )
            }

            var item = Self.makeItem(from: draft, hash: hash, blob: stored)
            try item.insert(db)
            return .inserted(item)
        }
    }

    private static func makeItem(from draft: ClipDraft, hash: String, blob: StoredBlob?) -> ClipItem {
        let now = Date()
        let preview = draft.text.map { previewSnippet($0) }

        var byteSize = (draft.text?.utf8.count ?? 0)
            + (draft.rtfData?.count ?? 0)
            + (draft.htmlText?.utf8.count ?? 0)
        if let blob { byteSize += blob.byteSize }

        let fileJSON: String?
        if draft.kind == .file, let data = try? JSONEncoder().encode(draft.fileURLs) {
            fileJSON = String(data: data, encoding: .utf8)
        } else {
            fileJSON = nil
        }

        return ClipItem(
            kind: draft.kind,
            text: draft.text,
            preview: preview,
            contentHash: hash,
            isFavorite: false,
            createdAt: now,
            updatedAt: now,
            byteSize: byteSize,
            rtfData: draft.rtfData,
            htmlText: draft.htmlText,
            imagePath: blob?.imagePath,
            thumbnailPath: blob?.thumbnailPath,
            pixelWidth: blob?.pixelWidth ?? draft.pixelWidth,
            pixelHeight: blob?.pixelHeight ?? draft.pixelHeight,
            fileURLsJSON: fileJSON,
            sourceAppBundleID: draft.sourceAppBundleID,
            sourceAppName: draft.sourceAppName
        )
    }

    static func previewSnippet(_ text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= ClipClassifier.previewLimit { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: ClipClassifier.previewLimit)
        return String(collapsed[..<end]) + "…"
    }

    // MARK: - Reading

    public func recent(limit: Int = 200, offset: Int = 0) throws -> [ClipItem] {
        try dbQueue.read { db in
            try ClipItem
                .order(ClipItem.Columns.updatedAt.desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }

    /// The most-recent items for the pinned top strip.
    public func topRecent(limit: Int = 10) throws -> [ClipItem] {
        try recent(limit: limit, offset: 0)
    }

    public func favorites(limit: Int = 500, offset: Int = 0) throws -> [ClipItem] {
        try dbQueue.read { db in
            try ClipItem
                .filter(ClipItem.Columns.isFavorite == true)
                .order(ClipItem.Columns.updatedAt.desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }

    public func item(id: Int64) throws -> ClipItem? {
        try dbQueue.read { db in try ClipItem.fetchOne(db, key: id) }
    }

    public func count(favoritesOnly: Bool = false) throws -> Int {
        try dbQueue.read { db in
            var request = ClipItem.all()
            if favoritesOnly { request = request.filter(ClipItem.Columns.isFavorite == true) }
            return try request.fetchCount(db)
        }
    }

    public func totalBytes() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(byteSize), 0) FROM clip") ?? 0
        }
    }

    // MARK: - Search

    public func search(_ query: SearchQuery) throws -> [ClipItem] {
        try dbQueue.read { db in
            var sql = "SELECT clip.* FROM clip"
            var wheres: [String] = []
            var args: [DatabaseValueConvertible] = []

            var ftsPattern: FTS5Pattern?
            if query.hasTextQuery {
                ftsPattern = Self.makeFTSPattern(query.trimmedText)
            }

            if query.hasTextQuery, let pattern = ftsPattern {
                sql += " JOIN clip_fts ON clip_fts.rowid = clip.id"
                wheres.append("clip_fts MATCH ?")
                args.append(pattern)
            } else if query.hasTextQuery {
                // Fallback for queries FTS can't parse.
                wheres.append("clip.text LIKE ? ESCAPE '\\'")
                args.append("%\(Self.escapeLike(query.trimmedText))%")
            }

            if query.favoritesOnly {
                wheres.append("clip.isFavorite = 1")
            }

            if !query.kinds.isEmpty {
                let placeholders = query.kinds.map { _ in "?" }.joined(separator: ", ")
                wheres.append("clip.kind IN (\(placeholders))")
                args.append(contentsOf: query.kinds.map { $0.rawValue })
            }

            if !wheres.isEmpty {
                sql += " WHERE " + wheres.joined(separator: " AND ")
            }
            sql += " ORDER BY clip.updatedAt DESC LIMIT ? OFFSET ?"
            args.append(query.limit)
            args.append(query.offset)

            return try ClipItem.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    /// Builds a prefix-matching FTS5 pattern (`"foo"* "bar"*`) so incremental typing
    /// matches. Tokens are quoted to neutralize FTS operators. Returns nil when the
    /// query has no usable tokens.
    static func makeFTSPattern(_ text: String) -> FTS5Pattern? {
        let tokens = text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        let raw = tokens.map { "\"\($0)\"*" }.joined(separator: " ")
        return try? FTS5Pattern(rawPattern: raw)
    }

    static func escapeLike(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    // MARK: - Mutations

    public func setFavorite(id: Int64, isFavorite: Bool) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clip SET isFavorite = ? WHERE id = ?",
                arguments: [isFavorite, id]
            )
        }
    }

    public func delete(id: Int64) throws {
        try dbQueue.write { db in
            if let item = try ClipItem.fetchOne(db, key: id) {
                _ = try item.delete(db)
                self.blobStore?.delete(imagePath: item.imagePath, thumbnailPath: item.thumbnailPath)
            }
        }
    }

    /// Deletes everything, optionally sparing favorites.
    public func clear(keepFavorites: Bool) throws {
        try dbQueue.write { db in
            let condition = keepFavorites ? "WHERE isFavorite = 0" : ""
            let items = try ClipItem.fetchAll(db, sql: "SELECT * FROM clip \(condition)")
            try db.execute(sql: "DELETE FROM clip \(condition)")
            for item in items {
                self.blobStore?.delete(imagePath: item.imagePath, thumbnailPath: item.thumbnailPath)
            }
        }
    }

    /// Prunes non-favorites that fall outside `policy`. Returns the pruned ids.
    @discardableResult
    public func applyRetention(_ policy: RetentionPolicy, now: Date = Date()) throws -> [Int64] {
        guard policy.hasAnyLimit else { return [] }
        return try dbQueue.write { db in
            let candidates = try Row.fetchAll(
                db,
                sql: "SELECT id, updatedAt, byteSize, isFavorite FROM clip"
            ).map { row -> RetentionCandidate in
                RetentionCandidate(
                    id: row["id"],
                    updatedAt: row["updatedAt"],
                    byteSize: row["byteSize"],
                    isFavorite: row["isFavorite"]
                )
            }

            let victims = policy.idsToPrune(from: candidates, now: now)
            guard !victims.isEmpty else { return [] }

            let victimIds = Array(victims)
            let victimItems = try ClipItem.filter(keys: victimIds).fetchAll(db)
            _ = try ClipItem.deleteAll(db, keys: victimIds)
            for item in victimItems {
                self.blobStore?.delete(imagePath: item.imagePath, thumbnailPath: item.thumbnailPath)
            }
            return victimIds
        }
    }

    // MARK: - Export support

    /// All items, newest first — used to build an export archive.
    public func allItems() throws -> [ClipItem] {
        try dbQueue.read { db in
            try ClipItem.order(ClipItem.Columns.updatedAt.desc).fetchAll(db)
        }
    }

    /// Absolute URL for an item's stored blob, if any.
    public func blobURL(for item: ClipItem) -> URL? {
        guard let path = item.imagePath, let blobStore else { return nil }
        return blobStore.absoluteURL(forRelativePath: path)
    }

    public func thumbnailURL(for item: ClipItem) -> URL? {
        guard let path = item.thumbnailPath, let blobStore else { return nil }
        return blobStore.absoluteURL(forRelativePath: path)
    }
}
