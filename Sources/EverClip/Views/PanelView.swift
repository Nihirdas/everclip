import SwiftUI
import EverClipCore

/// The dropdown panel: search + filters, the pinned top strip, Recent/Favorites
/// tabs, the scrolling history list, and a footer.
struct PanelView: View {
    @ObservedObject var appState: AppState
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)

            if appState.showTopStrip {
                TopStripView(
                    items: appState.topRecent,
                    thumbnailProvider: { appState.store.thumbnailURL(for: $0)?.path },
                    onActivate: { appState.activate($0) }
                )
                Divider().opacity(0.4)
            }

            tabBar
            Divider().opacity(0.4)

            content

            Divider().opacity(0.4)
            footer
        }
        .frame(width: 420, height: 560)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10))
        )
        .onAppear {
            appState.reload()
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Search clipboard…", text: $appState.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onChange(of: appState.searchText) { _ in appState.reload() }

            if !appState.searchText.isEmpty {
                IconButton(systemName: "xmark.circle.fill", help: "Clear search") {
                    appState.searchText = ""
                    appState.reload()
                }
            }

            typeFilterMenu

            IconButton(systemName: "gearshape", help: "Settings") {
                appState.onOpenSettings?()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var typeFilterMenu: some View {
        Menu {
            Button {
                appState.setTypeFilter(nil)
            } label: {
                Label("All Types", systemImage: appState.typeFilter == nil ? "checkmark" : "square.grid.2x2")
            }
            Divider()
            ForEach(ClipKind.allCases, id: \.self) { kind in
                Button {
                    appState.setTypeFilter(kind)
                } label: {
                    Label(kind.badgeLabel, systemImage: appState.typeFilter == kind ? "checkmark" : kind.symbolName)
                }
            }
        } label: {
            Image(systemName: appState.typeFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(appState.typeFilter == nil ? Color.secondary : Theme.accent)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Filter by type")
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 6) {
            TabPill(title: "Recent", systemImage: "clock", isActive: appState.selectedTab == .recent) {
                appState.selectTab(.recent)
            }
            TabPill(title: "Favorites", systemImage: "star", isActive: appState.selectedTab == .favorites) {
                appState.selectTab(.favorites)
            }
            Spacer()
            if appState.isPaused {
                Label("Paused", systemImage: "pause.circle.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Content

    private var content: some View {
        Group {
            if appState.items.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(appState.items) { item in
                                ClipRowView(
                                    item: item,
                                    isSelected: item.id == appState.selectionID,
                                    thumbnailPath: appState.store.thumbnailURL(for: item)?.path,
                                    onActivate: { appState.activate(item) },
                                    onTogglePin: { appState.togglePin(item) },
                                    onDelete: { appState.delete(item) }
                                )
                                .id(item.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .onChange(of: appState.selectionID) { id in
                        // `id` stays Int64? to match each row's `.id(item.id)` identity.
                        guard id != nil else { return }
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: appState.selectedTab == .favorites ? "star" : "doc.on.clipboard")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(emptyMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var emptyMessage: String {
        if !appState.searchText.isEmpty || appState.typeFilter != nil { return "No matching items." }
        if appState.selectedTab == .favorites { return "No favorites yet.\nPin an item with the star." }
        return "Nothing captured yet.\nCopy something and it appears here."
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(appState.totalCount) item\(appState.totalCount == 1 ? "" : "s")")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                appState.togglePause()
            } label: {
                Label(appState.isPaused ? "Resume" : "Pause", systemImage: appState.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10.5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(appState.isPaused ? "Resume capturing" : "Pause capturing")

            Menu {
                Button("Clear History (keep Favorites)") { appState.clearAll(keepFavorites: true) }
                Button("Clear Everything", role: .destructive) { appState.clearAll(keepFavorites: false) }
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(.system(size: 10.5))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct TabPill: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isActive ? Theme.accent.opacity(0.18) : .clear)
                .foregroundStyle(isActive ? Theme.accent : Color.secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
