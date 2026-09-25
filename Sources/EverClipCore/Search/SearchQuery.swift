import Foundation

/// A search/filter request against the history.
public struct SearchQuery: Equatable, Sendable {
    /// Free-text query. Empty means "no text filter" (browse mode).
    public var text: String
    /// Restrict to these kinds. Empty means all kinds.
    public var kinds: Set<ClipKind>
    /// Only return favorited items.
    public var favoritesOnly: Bool
    public var limit: Int
    public var offset: Int

    public init(
        text: String = "",
        kinds: Set<ClipKind> = [],
        favoritesOnly: Bool = false,
        limit: Int = 200,
        offset: Int = 0
    ) {
        self.text = text
        self.kinds = kinds
        self.favoritesOnly = favoritesOnly
        self.limit = limit
        self.offset = offset
    }

    public var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var hasTextQuery: Bool { !trimmedText.isEmpty }
}
