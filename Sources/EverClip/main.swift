import AppKit

// EverClip runs as a menu-bar agent (no Dock icon). LSUIElement in Info.plist
// makes it an accessory app; we also set the activation policy explicitly so it
// behaves correctly when launched directly (e.g. from `swift run`).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
