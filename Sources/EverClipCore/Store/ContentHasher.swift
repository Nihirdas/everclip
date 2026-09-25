import Foundation
import CryptoKit

/// Produces the stable `contentHash` used to collapse duplicates.
///
/// Text-like items hash their normalized text so re-copying the same snippet
/// bumps the existing row instead of inserting a new one. Images hash their bytes.
/// Files hash their (sorted) path list.
public enum ContentHasher {

    public static func hash(for draft: ClipDraft) -> String {
        switch draft.kind {
        case .text, .richText, .url:
            let normalized = (draft.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return digest(of: "\(draft.kind.rawValue):\(normalized)")
        case .image, .screenshot:
            if let data = draft.imageData {
                return digest(of: data, prefix: draft.kind.rawValue)
            }
            return digest(of: "\(draft.kind.rawValue):empty")
        case .file:
            let joined = draft.fileURLs.sorted().joined(separator: "\u{1f}")
            return digest(of: "file:\(joined)")
        }
    }

    static func digest(of string: String) -> String {
        digest(of: Data(string.utf8))
    }

    static func digest(of data: Data, prefix: String? = nil) -> String {
        var hasher = SHA256()
        if let prefix { hasher.update(data: Data("\(prefix):".utf8)) }
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
