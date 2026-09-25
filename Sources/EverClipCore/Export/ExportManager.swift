import Foundation

/// Orchestrates exports: builds one archive from the current history and ships it
/// to every enabled target. Also answers "is a scheduled run due?".
///
/// Nothing here runs unless the user has enabled export and configured a target.
public final class ExportManager {
    private let store: ClipStore
    private let settingsStore: SettingsStore
    private let workDirectory: URL
    private let openURL: (URL) -> Void
    private let keychain: KeychainStore

    public init(
        store: ClipStore,
        settingsStore: SettingsStore,
        workDirectory: URL,
        openURL: @escaping (URL) -> Void,
        keychain: KeychainStore = KeychainStore()
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.workDirectory = workDirectory
        self.openURL = openURL
        self.keychain = keychain
    }

    public func isDue(now: Date = Date()) -> Bool {
        let export = settingsStore.settings.export
        guard export.isEnabled, export.schedule != .off, hasEnabledTargets(export) else { return false }
        guard let last = export.lastRunAt else { return true }
        let interval: TimeInterval = export.schedule == .daily ? 86_400 : 7 * 86_400
        return now.timeIntervalSince(last) >= interval
    }

    /// Runs the export if the schedule says it's time; swallows errors (logged by caller if desired).
    public func runIfDue(now: Date = Date()) async {
        guard isDue(now: now) else { return }
        _ = try? await runNow()
    }

    /// Builds and ships the archive to all enabled targets immediately.
    @discardableResult
    public func runNow() async throws -> ClipArchive {
        let export = settingsStore.settings.export
        guard export.isEnabled else {
            throw ExportError.notConfigured("Export is turned off.")
        }
        let targets = makeTargets(from: export)
        guard !targets.isEmpty else {
            throw ExportError.notConfigured("No export targets are enabled.")
        }

        // Fresh staging area each run.
        try? FileManager.default.removeItem(at: workDirectory)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        let items = try store.allItems()
        let builder = ArchiveBuilder()
        let archive = try builder.build(
            items: items,
            blobURLProvider: { [store] in store.blobURL(for: $0) },
            includeBlobs: export.includeBlobs,
            into: workDirectory,
            zip: true
        )

        var firstError: Error?
        for target in targets {
            do {
                try await target.export(archive)
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        settingsStore.update { $0.export.lastRunAt = Date() }

        if let firstError { throw firstError }
        return archive
    }

    private func hasEnabledTargets(_ export: ExportSettings) -> Bool {
        export.targets.contains { $0.isEnabled }
    }

    private func makeTargets(from export: ExportSettings) -> [ExportTarget] {
        export.targets.filter { $0.isEnabled }.compactMap { config -> ExportTarget? in
            switch config.kind {
            case .localFolder:
                return LocalFolderExporter(config: config)
            case .googleDrive:
                return GoogleDriveExporter(config: config, openURL: openURL, keychain: keychain)
            case .gmail:
                return GmailExporter(config: config, openURL: openURL, keychain: keychain)
            }
        }
    }
}
