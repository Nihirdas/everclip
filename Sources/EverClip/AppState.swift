import SwiftUI
import EverClipCore

/// Observable UI state. Owns the currently displayed list and mediates every
/// action the panel can take, delegating side effects (paste, close, open
/// settings) back to `AppDelegate` via closures.
///
/// Only ever used on the main thread (AppKit callbacks and SwiftUI), so it is
/// left non-isolated to interoperate cleanly with the non-isolated AppKit glue.
final class AppState: ObservableObject {
    enum Tab: String { case recent, favorites }

    let store: ClipStore
    let settingsStore: SettingsStore

    @Published var items: [ClipItem] = []
    @Published var topRecent: [ClipItem] = []
    @Published var searchText: String = ""
    @Published var selectedTab: Tab = .recent
    @Published var typeFilter: ClipKind?
    @Published var selectionID: Int64?
    @Published var isPaused: Bool
    @Published var totalCount: Int = 0

    var onActivateItem: ((ClipItem) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRequestClose: (() -> Void)?

    init(store: ClipStore, settingsStore: SettingsStore) {
        self.store = store
        self.settingsStore = settingsStore
        self.isPaused = settingsStore.settings.isPaused
        reload()
    }

    var showTopStrip: Bool {
        selectedTab == .recent
            && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && typeFilter == nil
            && !topRecent.isEmpty
    }

    func reload() {
        let settings = settingsStore.settings
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let favoritesOnly = selectedTab == .favorites

        do {
            if !trimmed.isEmpty || typeFilter != nil {
                let kinds: Set<ClipKind> = typeFilter.map { [$0] } ?? []
                items = try store.search(SearchQuery(text: trimmed, kinds: kinds, favoritesOnly: favoritesOnly, limit: 500))
            } else if favoritesOnly {
                items = try store.favorites(limit: 1000)
            } else {
                items = try store.recent(limit: 500)
            }
            topRecent = try store.topRecent(limit: settings.topStripCount)
            totalCount = try store.count()
        } catch {
            items = []
            topRecent = []
        }

        // Keep the selection valid.
        if selectionID == nil || !items.contains(where: { $0.id == selectionID }) {
            selectionID = items.first?.id
        }
    }

    func handleCapture() { reload() }

    func selectTab(_ tab: Tab) {
        guard tab != selectedTab else { return }
        selectedTab = tab
        selectionID = nil
        reload()
    }

    func setTypeFilter(_ kind: ClipKind?) {
        typeFilter = kind
        reload()
    }

    func togglePause() {
        settingsStore.update { $0.isPaused.toggle() }
        isPaused = settingsStore.settings.isPaused
    }

    func togglePin(_ item: ClipItem) {
        guard let id = item.id else { return }
        try? store.setFavorite(id: id, isFavorite: !item.isFavorite)
        reload()
    }

    func delete(_ item: ClipItem) {
        guard let id = item.id else { return }
        try? store.delete(id: id)
        reload()
    }

    func clearAll(keepFavorites: Bool) {
        try? store.clear(keepFavorites: keepFavorites)
        reload()
    }

    func activate(_ item: ClipItem) {
        onActivateItem?(item)
    }

    func activateSelection() {
        guard let id = selectionID, let item = items.first(where: { $0.id == id }) else { return }
        activate(item)
    }

    /// Moves the highlighted row by `delta` (used by keyboard navigation).
    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let currentIndex = items.firstIndex(where: { $0.id == selectionID }) ?? -1
        let next = max(0, min(items.count - 1, currentIndex + delta))
        selectionID = items[next].id
    }

    /// Activates the Nth top-strip item (⌘1…⌘9). Returns whether it fired.
    @discardableResult
    func activateTopStripItem(at index: Int) -> Bool {
        guard index >= 0, index < topRecent.count else { return false }
        activate(topRecent[index])
        return true
    }
}
