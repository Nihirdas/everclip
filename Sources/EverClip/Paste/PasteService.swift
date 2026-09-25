import AppKit
import Carbon.HIToolbox
import CoreGraphics
import ApplicationServices

/// Simulates ⌘V to paste into whichever app is frontmost. This is the only part of
/// EverClip that needs Accessibility permission.
enum PasteService {
    /// Whether EverClip is trusted for Accessibility. Pass `prompt: true` to show
    /// the system prompt the first time.
    static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Posts a synthetic ⌘V keystroke to the frontmost application.
    static func pasteToFrontmostApp() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Opens the Accessibility pane of System Settings.
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
