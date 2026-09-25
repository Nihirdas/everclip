import AppKit
import SwiftUI

/// A borderless panel that can still become key (so the search field accepts input).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the dropdown panel: shows/hides it, positions it under the status item,
/// remembers the app to paste back into, and routes keyboard navigation.
final class PanelController {
    private let panel: KeyablePanel
    private let appState: AppState
    private var keyMonitor: Any?

    /// The app that was frontmost when the panel opened — the paste-back target.
    private(set) var previousApp: NSRunningApplication?

    init(appState: AppState) {
        self.appState = appState

        let hosting = NSHostingView(rootView: PanelView(appState: appState))
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .utilityWindow
        panel.contentView = hosting
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(relativeTo button: NSStatusBarButton?) {
        if isVisible { hide() } else { show(relativeTo: button) }
    }

    func show(relativeTo button: NSStatusBarButton?) {
        previousApp = NSWorkspace.shared.frontmostApplication
        position(relativeTo: button)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    // MARK: Positioning

    private func position(relativeTo button: NSStatusBarButton?) {
        let size = panel.frame.size
        let gap: CGFloat = 6

        if let button, let buttonWindow = button.window {
            let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = buttonWindow.screen ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

            var x = buttonRect.midX - size.width + 20
            x = max(visible.minX + 8, min(x, visible.maxX - size.width - 8))
            let y = buttonRect.minY - size.height - gap
            panel.setFrameOrigin(NSPoint(x: x, y: max(visible.minY + 8, y)))
        } else {
            // Hotkey with no anchor: top-center of the screen under the mouse.
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let x = min(max(mouse.x - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
            let y = visible.maxY - size.height - gap
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    // MARK: Keyboard navigation

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 125: appState.moveSelection(1); return nil   // ↓
        case 126: appState.moveSelection(-1); return nil  // ↑
        case 36, 76: appState.activateSelection(); return nil // return / enter
        case 53: hide(); return nil                        // esc
        default:
            if event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers,
               let n = Int(chars), n >= 1, n <= 9,
               appState.activateTopStripItem(at: n - 1) {
                return nil
            }
            return event
        }
    }
}
