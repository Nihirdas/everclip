import Foundation

/// Rules for how much history to keep. Any `nil` field means "no limit" for that
/// dimension. Favorites are never counted against a limit and are never pruned.
public struct RetentionPolicy: Codable, Equatable, Sendable {
    /// Prune non-favorites older than this many days.
    public var maxDays: Int?
    /// Keep at most this many non-favorite items (newest kept).
    public var maxItems: Int?
    /// Keep the total byte footprint of non-favorites under this.
    public var maxDiskBytes: Int?

    public init(maxDays: Int? = nil, maxItems: Int? = nil, maxDiskBytes: Int? = nil) {
        self.maxDays = maxDays
        self.maxItems = maxItems
        self.maxDiskBytes = maxDiskBytes
    }

    public static let unlimited = RetentionPolicy()

    /// A sensible default: no age limit, up to 10k items, up to ~2 GB on disk.
    public static let standard = RetentionPolicy(maxDays: nil, maxItems: 10_000, maxDiskBytes: 2_000_000_000)

    public var hasAnyLimit: Bool {
        maxDays != nil || maxItems != nil || maxDiskBytes != nil
    }
}

/// The minimal facts about an item needed to decide whether it should be pruned.
public struct RetentionCandidate: Equatable, Sendable {
    public let id: Int64
    public let updatedAt: Date
    public let byteSize: Int
    public let isFavorite: Bool

    public init(id: Int64, updatedAt: Date, byteSize: Int, isFavorite: Bool) {
        self.id = id
        self.updatedAt = updatedAt
        self.byteSize = byteSize
        self.isFavorite = isFavorite
    }
}

public extension RetentionPolicy {
    /// Returns the ids that should be pruned under this policy.
    ///
    /// Favorites are always kept. Among non-favorites (newest first) an item is
    /// pruned if it is older than `maxDays`, or falls outside the newest `maxItems`,
    /// or pushes the running byte total past `maxDiskBytes`.
    func idsToPrune(from candidates: [RetentionCandidate], now: Date = Date()) -> Set<Int64> {
        guard hasAnyLimit else { return [] }

        // Newest first; favorites are excluded entirely.
        let nonFavorites = candidates
            .filter { !$0.isFavorite }
            .sorted { $0.updatedAt > $1.updatedAt }

        var victims = Set<Int64>()

        if let maxDays, maxDays >= 0 {
            let cutoff = now.addingTimeInterval(-Double(maxDays) * 86_400)
            for c in nonFavorites where c.updatedAt < cutoff {
                victims.insert(c.id)
            }
        }

        if let maxItems, maxItems >= 0 {
            for c in nonFavorites.dropFirst(maxItems) {
                victims.insert(c.id)
            }
        }

        if let maxDiskBytes, maxDiskBytes >= 0 {
            var running = 0
            for c in nonFavorites {
                running += max(0, c.byteSize)
                if running > maxDiskBytes {
                    victims.insert(c.id)
                }
            }
        }

        return victims
    }
}
