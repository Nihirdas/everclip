import Foundation
import GRDB

/// Database bootstrap: opens a queue and runs migrations, including the FTS5
/// full-text index that mirrors the `clip.text` column.
public enum ClipDatabase {

    public static let fileName = "everclip.sqlite"

    public static func makeQueue(at url: URL) throws -> DatabaseQueue {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(path: url.path, configuration: config)
        try migrator.migrate(queue)
        return queue
    }

    /// In-memory database, used by tests.
    public static func makeInMemoryQueue() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try migrator.migrate(queue)
        return queue
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_clip") { db in
            try db.create(table: "clip") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull()
                t.column("text", .text)
                t.column("preview", .text)
                t.column("contentHash", .text).notNull().indexed()
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull().indexed()
                t.column("byteSize", .integer).notNull().defaults(to: 0)
                t.column("rtfData", .blob)
                t.column("htmlText", .text)
                t.column("imagePath", .text)
                t.column("thumbnailPath", .text)
                t.column("pixelWidth", .integer)
                t.column("pixelHeight", .integer)
                t.column("fileURLsJSON", .text)
                t.column("sourceAppBundleID", .text)
                t.column("sourceAppName", .text)
            }

            // Full-text search over the plain-text form, kept in sync via triggers.
            try db.create(virtualTable: "clip_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clip")
                t.column("text")
                t.tokenizer = .porter(wrapping: .unicode61())
            }
        }

        return migrator
    }
}
