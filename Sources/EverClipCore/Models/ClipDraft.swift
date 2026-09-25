import Foundation

/// Content ready to be stored, before it has been persisted or hashed.
///
/// The app builds a draft from a `PasteboardSnapshot` via `ClipClassifier`, then
/// hands it to `ClipStore`, which computes the hash, writes any blobs, and inserts.
public struct ClipDraft: Sendable {
    public var kind: ClipKind
    public var text: String?
    public var rtfData: Data?
    public var htmlText: String?

    /// Raw image bytes to persist to disk (for `.image` / `.screenshot`).
    public var imageData: Data?
    /// Preferred file extension for the image blob (e.g. "png", "tiff").
    public var imageFileExtension: String?
    public var pixelWidth: Int?
    public var pixelHeight: Int?

    /// File paths for `.file` items.
    public var fileURLs: [String]

    public var sourceAppBundleID: String?
    public var sourceAppName: String?

    public init(
        kind: ClipKind,
        text: String? = nil,
        rtfData: Data? = nil,
        htmlText: String? = nil,
        imageData: Data? = nil,
        imageFileExtension: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        fileURLs: [String] = [],
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.kind = kind
        self.text = text
        self.rtfData = rtfData
        self.htmlText = htmlText
        self.imageData = imageData
        self.imageFileExtension = imageFileExtension
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fileURLs = fileURLs
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
    }
}
