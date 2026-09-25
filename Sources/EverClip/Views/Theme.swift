import SwiftUI
import AppKit
import EverClipCore

/// Visual tokens and small formatting helpers shared across the UI.
enum Theme {
    static let accent = Color(red: 0.38, green: 0.45, blue: 0.98)      // indigo
    static let panelCornerRadius: CGFloat = 14
    static let rowCornerRadius: CGFloat = 8

    static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func relativeTime(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

extension ClipKind {
    var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .richText: return "textformat"
        case .url: return "link"
        case .image: return "photo"
        case .screenshot: return "camera.viewfinder"
        case .file: return "doc"
        }
    }

    var tint: Color {
        switch self {
        case .text: return Color(red: 0.55, green: 0.58, blue: 0.66)
        case .richText: return Color(red: 0.55, green: 0.45, blue: 0.85)
        case .url: return Color(red: 0.20, green: 0.55, blue: 0.90)
        case .image: return Color(red: 0.20, green: 0.66, blue: 0.52)
        case .screenshot: return Color(red: 0.90, green: 0.55, blue: 0.25)
        case .file: return Color(red: 0.85, green: 0.42, blue: 0.55)
        }
    }
}

/// Small in-memory cache so thumbnail files aren't re-read on every redraw.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private var cache = NSCache<NSString, NSImage>()

    func image(atPath path: String) -> NSImage? {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}

extension ByteCountFormatter {
    static func short(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
