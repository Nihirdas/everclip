import SwiftUI
import AppKit
import Carbon.HIToolbox
import EverClipCore

/// Formats a Carbon keycode + Carbon modifier mask as a menu-style shortcut
/// string, e.g. `⌥⌘V`.
enum HotKeyFormatter {
    static func string(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        var out = ""
        if carbonModifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { out += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { out += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { out += "⌘" }
        out += keyName(keyCode)
        return out
    }

    static func keyName(_ keyCode: UInt32) -> String {
        names[Int(keyCode)] ?? "Key \(keyCode)"
    }

    private static let names: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_Escape: "⎋", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12"
    ]

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        return mods
    }
}

/// A SwiftUI control for recording the global hotkey. Click it, then press the
/// desired combination (must include at least one of ⌘ ⌥ ⌃). Esc cancels.
struct HotKeyRecorder: NSViewRepresentable {
    @Binding var hotKey: HotKeyConfig

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.hotKey = hotKey
        button.onCapture = { keyCode, modifiers in
            var updated = hotKey
            updated.keyCode = keyCode
            updated.modifiers = modifiers
            hotKey = updated
        }
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.hotKey = hotKey
    }
}

/// NSButton that records a key combination while it is the first responder.
final class RecorderButton: NSButton {
    var onCapture: ((UInt32, UInt32) -> Void)?

    var hotKey: HotKeyConfig = .defaultHotKey {
        didSet { if !recording { refreshTitle() } }
    }

    private var recording = false {
        didSet { refreshTitle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        target = self
        action = #selector(beginRecording)
        refreshTitle()
    }

    @objc private func beginRecording() {
        recording = true
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        return capture(event)
    }

    override func keyDown(with event: NSEvent) {
        if recording, capture(event) { return }
        super.keyDown(with: event)
    }

    private func capture(_ event: NSEvent) -> Bool {
        // Esc cancels without changing the shortcut.
        if event.keyCode == UInt16(kVK_Escape) {
            recording = false
            window?.makeFirstResponder(nil)
            return true
        }

        // Require at least one of Command / Option / Control.
        let required: NSEvent.ModifierFlags = [.command, .option, .control]
        guard !event.modifierFlags.intersection(required).isEmpty else {
            NSSound.beep()
            return true
        }

        let keyCode = UInt32(event.keyCode)
        let modifiers = HotKeyFormatter.carbonModifiers(from: event.modifierFlags)
        var updated = hotKey
        updated.keyCode = keyCode
        updated.modifiers = modifiers
        hotKey = updated
        onCapture?(keyCode, modifiers)

        recording = false
        window?.makeFirstResponder(nil)
        return true
    }

    private func refreshTitle() {
        title = recording
            ? "Type shortcut…"
            : HotKeyFormatter.string(keyCode: hotKey.keyCode, carbonModifiers: hotKey.modifiers)
    }
}
