import Foundation

/// Builds a portable export archive: a folder containing `manifest.json` and,
/// optionally, copies of image/screenshot blobs. Can also zip the folder for
/// single-file transports (email attachment, Drive upload).
public final class ArchiveBuilder {
    private let fileManager = FileManager.default

    public init() {}

    public func build(
        items: [ClipItem],
        blobURLProvider: (ClipItem) -> URL?,
        includeBlobs: Bool,
        into parentDirectory: URL,
        zip: Bool,
        now: Date = Date()
    ) throws -> ClipArchive {
        let stamp = Self.timestamp(now)
        let dirName = "EverClip-Export-\(stamp)"
        let dir = parentDirectory.appendingPathComponent(dirName, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        var manifestItems: [ArchiveManifestItem] = []
        manifestItems.reserveCapacity(items.count)

        let blobsDir = dir.appendingPathComponent("blobs", isDirectory: true)
        var madeBlobsDir = false

        for item in items {
            var blobRelative: String?
            if includeBlobs, item.kind.isBinary, let src = blobURLProvider(item),
               fileManager.fileExists(atPath: src.path) {
                if !madeBlobsDir {
                    try fileManager.createDirectory(at: blobsDir, withIntermediateDirectories: true)
                    madeBlobsDir = true
                }
                let dest = blobsDir.appendingPathComponent(src.lastPathComponent)
                if !fileManager.fileExists(atPath: dest.path) {
                    try fileManager.copyItem(at: src, to: dest)
                }
                blobRelative = "blobs/\(src.lastPathComponent)"
            }
            manifestItems.append(ArchiveManifestItem(from: item, blobPath: blobRelative))
        }

        let manifest = ArchiveManifest(createdAt: now, items: manifestItems)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)

        var zipURL: URL?
        if zip {
            zipURL = try Self.zipDirectory(dir, named: dirName, in: parentDirectory)
        }

        return ClipArchive(directoryURL: dir, zipURL: zipURL, itemCount: items.count, createdAt: now)
    }

    /// Zips a directory using NSFileCoordinator's `.forUploading` option, which
    /// produces a standard zip without any third-party dependency.
    static func zipDirectory(_ directory: URL, named: String, in parentDirectory: URL) throws -> URL {
        let destination = parentDirectory.appendingPathComponent("\(named).zip")
        try? FileManager.default.removeItem(at: destination)

        var coordError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: directory, options: [.forUploading], error: &coordError) { tempZipURL in
            do {
                try FileManager.default.copyItem(at: tempZipURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordError { throw ExportError.archiveFailed(coordError.localizedDescription) }
        if let copyError { throw ExportError.archiveFailed(copyError.localizedDescription) }
        return destination
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}
