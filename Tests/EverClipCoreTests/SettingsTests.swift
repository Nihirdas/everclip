import Testing
import Foundation
@testable import EverClipCore

@Suite struct SettingsTests {
    @Test func defaults() {
        let settings = AppSettings.default
        #expect(settings.pollingIntervalMilliseconds == 300)
        #expect(settings.topStripCount == 10)
        #expect(!settings.isPaused)
        #expect(settings.hotKey == .defaultHotKey)
        #expect(settings.hotKey.keyCode == 9) // V
    }

    @Test func codableRoundTrip() throws {
        var settings = AppSettings.default
        settings.excludedBundleIDs = ["com.apple.Safari"]
        settings.retention = RetentionPolicy(maxDays: 30, maxItems: 500, maxDiskBytes: 1_000_000)
        settings.export.targets = [ExportTargetConfig(kind: .localFolder, isEnabled: true, localFolderPath: "/tmp/x")]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(settings)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(AppSettings.self, from: data)
        #expect(restored == settings)
    }

    @Test func settingsStorePersists() throws {
        let dir = TestSupport.makeTempDir()
        defer { TestSupport.remove(dir) }
        let url = dir.appendingPathComponent("settings.json")

        let store = SettingsStore(url: url)
        var changed: AppSettings?
        store.onChange = { changed = $0 }
        store.update { $0.isPaused = true; $0.topStripCount = 5 }

        #expect(changed?.isPaused == true)

        let reloaded = SettingsStore(url: url)
        #expect(reloaded.settings.isPaused)
        #expect(reloaded.settings.topStripCount == 5)
    }

    @Test func updateNoOpWhenUnchanged() throws {
        let dir = TestSupport.makeTempDir()
        defer { TestSupport.remove(dir) }
        let store = SettingsStore(url: dir.appendingPathComponent("s.json"))
        var callbacks = 0
        store.onChange = { _ in callbacks += 1 }
        store.update { $0.isPaused = false } // already false
        #expect(callbacks == 0)
    }
}
