import AppKit
import EverClipCore

/// Polls `NSPasteboard` for changes and records new content, applying the pause
/// switch, the per-app exclude list, and the privacy filters.
final class PasteboardMonitor {
    var onCapture: (() -> Void)?

    private let pasteboard = NSPasteboard.general
    private let store: ClipStore
    private let classifier = ClipClassifier()
    private let settingsProvider: () -> AppSettings

    private var timer: Timer?
    private var lastChangeCount: Int

    init(store: ClipStore, settingsProvider: @escaping () -> AppSettings) {
        self.store = store
        self.settingsProvider = settingsProvider
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Re-reads the polling interval after settings change.
    func reschedule() {
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = max(0.05, Double(settingsProvider().pollingIntervalMilliseconds) / 1000.0)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common so polling continues while menus/panels track the run loop.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        let settings = settingsProvider()

        // Paused: swallow this change so it isn't captured now or on resume.
        if settings.isPaused { return }

        // Per-app exclusion.
        let frontApp = NSWorkspace.shared.frontmostApplication
        if let bundleID = frontApp?.bundleIdentifier, settings.excludedBundleIDs.contains(bundleID) {
            return
        }

        guard let snapshot = buildSnapshot(frontApp: frontApp) else { return }
        guard let draft = classifier.makeDraft(from: snapshot) else { return }

        do {
            let outcome = try store.store(draft)
            if outcome.item != nil {
                onCapture?()
            }
        } catch {
            NSLog("EverClip: failed to store clipboard item: \(error.localizedDescription)")
        }
    }

    /// Reads the current pasteboard into a platform-neutral snapshot.
    private func buildSnapshot(frontApp: NSRunningApplication?) -> PasteboardSnapshot? {
        let rawTypes = (pasteboard.types ?? []).map { $0.rawValue }
        guard !rawTypes.isEmpty else { return nil }

        let isConcealed = rawTypes.contains { PasteboardTypes.privacySensitive.contains($0) }

        var snapshot = PasteboardSnapshot(
            types: rawTypes,
            isConcealed: isConcealed,
            sourceAppBundleID: frontApp?.bundleIdentifier,
            sourceAppName: frontApp?.localizedName
        )

        // File URLs (Finder copies, etc.).
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL], !urls.isEmpty {
            snapshot.fileURLs = urls.map { $0.path }
        }

        // Image bytes (prefer PNG, fall back to TIFF).
        if let png = pasteboard.data(forType: .png) {
            snapshot.imageData = png
            snapshot.imageFileExtension = "png"
        } else if let tiff = pasteboard.data(forType: .tiff) {
            snapshot.imageData = tiff
            snapshot.imageFileExtension = "tiff"
        }

        // Text-like payloads.
        snapshot.plainText = pasteboard.string(forType: .string)
        snapshot.html = pasteboard.string(forType: .html)
        snapshot.rtf = pasteboard.data(forType: .rtf)

        // A dedicated web URL, if the app advertised one.
        if let urlString = pasteboard.string(forType: NSPasteboard.PasteboardType("public.url")),
           urlString.lowercased().hasPrefix("http") {
            snapshot.urlString = urlString
        }

        return snapshot
    }
}
