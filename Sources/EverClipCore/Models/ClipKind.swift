import Foundation

/// The category of a captured clipboard item.
///
/// Stored in the database as its `rawValue`, so existing rows keep working as
/// long as these string values are stable.
public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text
    case richText
    case url
    case image
    case screenshot
    case file

    /// Whether the item's payload lives on disk (as opposed to inline text).
    public var isBinary: Bool {
        switch self {
        case .image, .screenshot:
            return true
        case .text, .richText, .url, .file:
            return false
        }
    }

    /// A short, human-facing label used for the type badge.
    public var badgeLabel: String {
        switch self {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .url: return "Link"
        case .image: return "Image"
        case .screenshot: return "Screenshot"
        case .file: return "File"
        }
    }
}
