import AppKit
import SwiftUI
import EverClipCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ClipStore!
    private var settingsStore: SettingsStore!
    private var appState: AppState!
    private var monitor: PasteboardMonitor!
    private var hotKey: HotKeyManager!
    private var panelController: PanelController!
    private var exportManager: ExportManager!

    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var settingsModel: SettingsModel!

    private var maintenanceTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStores()
        setUpState()
        setUpStatusItem()
        setUpMonitorAndHotKey()
        applySettings(settingsStore.settings)

        runMaintenance()
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.runMaintenance()
        }
    }

    // MARK: - Setup

    private func setUpStores() {
        do {
            let dir = try EverClipPaths.storeDirectory()
            store = try ClipStore(directory: dir)
            let settingsURL = try EverClipPaths.settingsURL()
            settingsStore = SettingsStore(url: settingsURL)
        } catch {
            NSLog("EverClip: falling back to in-memory store: \(error.localizedDescription)")
            store = try! ClipStore.inMemory()
            settingsStore = SettingsStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("everclip-settings.json"))
        }

        let workDir = (try? EverClipPaths.applicationSupportDirectory().appendingPathComponent("export-staging"))
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("everclip-export")
        exportManager = ExportManager(
            store: store,
            settingsStore: settingsStore,
            workDirectory: workDir,
            openURL: { url in NSWorkspace.shared.open(url) }
        )
    }

    private func setUpState() {
        appState = AppState(store: store, settingsStore: settingsStore)
        panelController = PanelController(appState: appState)

        appState.onActivateItem = { [weak self] item in self?.activateAndPaste(item) }
        appState.onOpenSettings = { [weak self] in self?.openSettings() }
        appState.onRequestClose = { [weak self] in self?.panelController.hide() }
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "EverClip")
            button.image?.isTemplate = true
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func setUpMonitorAndHotKey() {
        monitor = PasteboardMonitor(store: store, settingsProvider: { [weak self] in
            self?.settingsStore.settings ?? .default
        })
        monitor.onCapture = { [weak self] in
            DispatchQueue.main.async { self?.appState.handleCapture() }
        }
        monitor.start()

        hotKey = HotKeyManager()
        hotKey.onFire = { [weak self] in self?.togglePanel() }
    }

    // MARK: - Status item interaction

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        settingsModel?.sync()
        panelController.toggle(relativeTo: statusItem.button)
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open EverClip", action: #selector(menuOpenPanel), keyEquivalent: "")
        let pauseTitle = settingsStore.settings.isPaused ? "Resume Capturing" : "Pause Capturing"
        menu.addItem(withTitle: pauseTitle, action: #selector(menuTogglePause), keyEquivalent: "")
        menu.addItem(.separator())
        if settingsStore.settings.export.isEnabled {
            menu.addItem(withTitle: "Back Up Now", action: #selector(menuBackupNow), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Settings…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit EverClip", action: #selector(menuQuit), keyEquivalent: "q")
        for item in menu.items { item.target = self }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // restore left-click toggle behavior
    }

    @objc private func menuOpenPanel() { togglePanel() }
    @objc private func menuTogglePause() { appState.togglePause(); settingsModel?.sync() }
    @objc private func menuBackupNow() { backupNow() }
    @objc private func menuOpenSettings() { openSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - Paste-back

    private func activateAndPaste(_ item: ClipItem) {
        ClipboardWriter.write(item, store: store)
        let target = panelController.previousApp
        panelController.hide()

        let shouldPaste = settingsStore.settings.pasteOnSelect
        target?.activate()

        guard shouldPaste else { return }
        if PasteService.hasAccessibilityPermission(prompt: false) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                PasteService.pasteToFrontmostApp()
            }
        } else {
            // Content is on the clipboard; user can paste manually. Nudge once.
            _ = PasteService.hasAccessibilityPermission(prompt: true)
        }
    }

    // MARK: - Settings

    private func openSettings() {
        panelController.hide()
        if settingsModel == nil {
            settingsModel = SettingsModel(store: settingsStore)
            settingsModel.onApply = { [weak self] settings in self?.applySettings(settings) }
        }
        settingsModel.sync()

        if settingsWindow == nil {
            let view = SettingsView(
                model: settingsModel,
                appVersion: Self.appVersion,
                onExportNow: { [weak self] in self?.backupNow() },
                onPruneNow: { [weak self] in self?.pruneNow() },
                onRequestAccessibility: { _ = PasteService.hasAccessibilityPermission(prompt: true) }
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 430),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "EverClip Settings"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Re-applies configuration that lives outside the store (hotkey, login item,
    /// appearance, poll interval).
    private func applySettings(_ settings: AppSettings) {
        if settings.hotKey.isEnabled {
            hotKey.register(keyCode: settings.hotKey.keyCode, modifiers: settings.hotKey.modifiers)
        } else {
            hotKey.unregister()
        }

        LaunchAtLogin.set(settings.launchAtLogin)
        monitor.reschedule()
        applyAppearance(settings.forcedDarkMode)
        appState.isPaused = settings.isPaused
        appState.reload()
    }

    private func applyAppearance(_ forcedDark: Bool?) {
        switch forcedDark {
        case nil: NSApp.appearance = nil
        case .some(true): NSApp.appearance = NSAppearance(named: .darkAqua)
        case .some(false): NSApp.appearance = NSAppearance(named: .aqua)
        }
    }

    // MARK: - Maintenance

    private func runMaintenance() {
        do {
            _ = try store.applyRetention(settingsStore.settings.retention)
            appState.reload()
        } catch {
            NSLog("EverClip: retention failed: \(error.localizedDescription)")
        }
        Task { await exportManager.runIfDue() }
    }

    private func pruneNow() {
        do {
            let pruned = try store.applyRetention(settingsStore.settings.retention)
            appState.reload()
            notify(title: "Pruned \(pruned.count) item\(pruned.count == 1 ? "" : "s")")
        } catch {
            notify(title: "Prune failed", body: error.localizedDescription)
        }
    }

    private func backupNow() {
        Task {
            do {
                let archive = try await exportManager.runNow()
                await MainActor.run { self.notify(title: "Backed up \(archive.itemCount) items") }
            } catch {
                await MainActor.run { self.notify(title: "Backup failed", body: error.localizedDescription) }
            }
        }
    }

    private func notify(title: String, body: String = "") {
        let alert = NSAlert()
        alert.messageText = title
        if !body.isEmpty { alert.informativeText = body }
        alert.alertStyle = .informational
        alert.runModal()
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
}
