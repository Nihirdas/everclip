import Foundation

/// A destination that can receive an export archive.
///
/// New backends (S3, WebDAV, Dropbox, …) only need to implement this protocol and
/// be constructed from an `ExportTargetConfig`; nothing else in the app changes.
public protocol ExportTarget {
    var kind: ExportTargetKind { get }
    var displayName: String { get }
    /// Ships the archive to the destination. May run for a while; call off-main.
    func export(_ archive: ClipArchive) async throws
}
