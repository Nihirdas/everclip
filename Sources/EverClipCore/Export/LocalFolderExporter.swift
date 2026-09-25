import Foundation

/// Copies the archive into a destination folder.
///
/// This is the fully-offline export path. Point `destinationFolder` at a Google
/// Drive, iCloud Drive, or Dropbox *synced folder* and you get off-machine backups
/// with zero OAuth — the sync client does the uploading.
public final class LocalFolderExporter: ExportTarget {
    public let kind: ExportTargetKind = .localFolder
    public var displayName: String { "Folder" }

    private let destinationFolder: URL
    /// Prefer copying the single zip when available.
    private let preferZip: Bool

    public init(destinationFolder: URL, preferZip: Bool = true) {
        self.destinationFolder = destinationFolder
        self.preferZip = preferZip
    }

    public convenience init?(config: ExportTargetConfig) {
        guard let path = config.localFolderPath, !path.isEmpty else { return nil }
        self.init(destinationFolder: URL(fileURLWithPath: path, isDirectory: true))
    }

    public func export(_ archive: ClipArchive) async throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        } catch {
            throw ExportError.transportFailed("Cannot create destination folder: \(error.localizedDescription)")
        }

        let source = (preferZip ? archive.zipURL : nil) ?? archive.zipURL ?? archive.directoryURL
        let destination = destinationFolder.appendingPathComponent(source.lastPathComponent)

        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: source, to: destination)
        } catch {
            throw ExportError.transportFailed(error.localizedDescription)
        }
    }
}
