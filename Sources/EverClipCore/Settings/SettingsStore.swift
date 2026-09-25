import Foundation

/// Loads and persists `AppSettings` as JSON. Kept UI-agnostic; the app layer
/// bridges `onChange` into its own observable state.
public final class SettingsStore {
    private let url: URL
    public private(set) var settings: AppSettings

    /// Invoked after every successful `update(_:)`.
    public var onChange: ((AppSettings) -> Void)?

    public init(url: URL) {
        self.url = url
        self.settings = SettingsStore.load(from: url) ?? .default
    }

    /// Mutates settings in place, persists, and notifies observers.
    public func update(_ mutate: (inout AppSettings) -> Void) {
        var updated = settings
        mutate(&updated)
        guard updated != settings else { return }
        settings = updated
        save()
        onChange?(updated)
    }

    public func reload() {
        if let loaded = SettingsStore.load(from: url) {
            settings = loaded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(settings)
            try data.write(to: url, options: .atomic)
        } catch {
            // Non-fatal: settings simply won't persist this change.
        }
    }

    private static func load(from url: URL) -> AppSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppSettings.self, from: data)
    }
}
