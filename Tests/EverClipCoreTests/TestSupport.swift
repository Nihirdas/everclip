import Foundation
@testable import EverClipCore

/// Shared helpers for the core test suite.
enum TestSupport {
    /// A unique temporary directory. Callers remove it when done.
    static func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("everclip-tests")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// A valid 1×1 PNG, used to exercise the blob/thumbnail path.
    static var onePixelPNG: Data {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        return Data(base64Encoded: base64)!
    }

    static func textSnapshot(_ text: String, sourceApp: String? = nil) -> PasteboardSnapshot {
        PasteboardSnapshot(types: ["public.utf8-plain-text"], plainText: text, sourceAppName: sourceApp)
    }
}
