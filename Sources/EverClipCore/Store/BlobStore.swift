import Foundation
#if canImport(ImageIO)
import ImageIO
import CoreGraphics
#endif

/// Result of persisting a binary payload to disk.
public struct StoredBlob: Sendable {
    public let imagePath: String        // relative to the blob root
    public let thumbnailPath: String?   // relative to the blob root
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let byteSize: Int
}

/// Stores image/screenshot bytes on disk and generates thumbnails.
///
/// Files are laid out as `blobs/<hash>.<ext>` and `thumbnails/<hash>.jpg`, with
/// paths kept relative so the database is portable if the store folder moves.
public final class BlobStore {
    public let root: URL
    private let blobsDir: URL
    private let thumbsDir: URL
    private let fileManager = FileManager.default

    /// Longest edge of a generated thumbnail, in pixels.
    public var thumbnailMaxPixelSize = 480

    public init(root: URL) throws {
        self.root = root
        self.blobsDir = root.appendingPathComponent("blobs", isDirectory: true)
        self.thumbsDir = root.appendingPathComponent("thumbnails", isDirectory: true)
        try fileManager.createDirectory(at: blobsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
    }

    public func absoluteURL(forRelativePath relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    /// Persists image bytes and a thumbnail. `hash` keys the filenames.
    public func writeImage(_ data: Data, fileExtension: String, hash: String) throws -> StoredBlob {
        let ext = Self.sanitize(fileExtension)
        let imageName = "\(hash).\(ext)"
        let imageURL = blobsDir.appendingPathComponent(imageName)
        try data.write(to: imageURL, options: .atomic)

        var thumbRelative: String?
        var width: Int?
        var height: Int?
        var thumbBytes = 0

        #if canImport(ImageIO)
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                width = props[kCGImagePropertyPixelWidth] as? Int
                height = props[kCGImagePropertyPixelHeight] as? Int
            }
            let thumbName = "\(hash).jpg"
            let thumbURL = thumbsDir.appendingPathComponent(thumbName)
            if writeThumbnail(from: source, to: thumbURL) {
                thumbRelative = "thumbnails/\(thumbName)"
                thumbBytes = (try? fileManager.attributesOfItem(atPath: thumbURL.path)[.size] as? Int) ?? 0
            }
        }
        #endif

        return StoredBlob(
            imagePath: "blobs/\(imageName)",
            thumbnailPath: thumbRelative,
            pixelWidth: width,
            pixelHeight: height,
            byteSize: data.count + thumbBytes
        )
    }

    /// Deletes the blob and (if present) its thumbnail, ignoring missing files.
    public func delete(imagePath: String?, thumbnailPath: String?) {
        for path in [imagePath, thumbnailPath].compactMap({ $0 }) {
            let url = root.appendingPathComponent(path)
            try? fileManager.removeItem(at: url)
        }
    }

    #if canImport(ImageIO)
    private func writeThumbnail(from source: CGImageSource, to url: URL) -> Bool {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return false
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            return false
        }
        let destOptions: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
        CGImageDestinationAddImage(dest, thumb, destOptions as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }
    #endif

    private static func sanitize(_ ext: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let cleaned = ext.lowercased().unicodeScalars.filter { allowed.contains($0) }
        let result = String(String.UnicodeScalarView(cleaned))
        return result.isEmpty ? "bin" : result
    }
}
