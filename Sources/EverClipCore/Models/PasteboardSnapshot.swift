import Foundation

/// A platform-neutral snapshot of the system pasteboard at a moment in time.
///
/// The macOS app fills this in from `NSPasteboard`; keeping it free of AppKit lets
/// the classifier be plain, testable logic and lets a future Windows port feed the
/// same core (see ROADMAP in the README).
public struct PasteboardSnapshot: Sendable {
    /// Raw type identifiers present on the pasteboard (UTIs on macOS).
    public var types: [String]
    public var plainText: String?
    public var html: String?
    public var rtf: Data?
    public var imageData: Data?
    /// Preferred image extension derived from the image type, e.g. "png".
    public var imageFileExtension: String?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var fileURLs: [String]
    /// A URL advertised directly by the pasteboard (`public.url`).
    public var urlString: String?

    /// Item is marked as concealed (e.g. `org.nspasteboard.ConcealedType`,
    /// typically set by password managers) and must never be stored.
    public var isConcealed: Bool
    /// Item is marked transient (`org.nspasteboard.TransientType`) and should be skipped.
    public var isTransient: Bool

    public var sourceAppBundleID: String?
    public var sourceAppName: String?

    public init(
        types: [String] = [],
        plainText: String? = nil,
        html: String? = nil,
        rtf: Data? = nil,
        imageData: Data? = nil,
        imageFileExtension: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        fileURLs: [String] = [],
        urlString: String? = nil,
        isConcealed: Bool = false,
        isTransient: Bool = false,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.types = types
        self.plainText = plainText
        self.html = html
        self.rtf = rtf
        self.imageData = imageData
        self.imageFileExtension = imageFileExtension
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fileURLs = fileURLs
        self.urlString = urlString
        self.isConcealed = isConcealed
        self.isTransient = isTransient
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
    }
}
