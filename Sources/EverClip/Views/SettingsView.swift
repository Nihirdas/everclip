import SwiftUI
import AppKit
import EverClipCore

/// Observable wrapper around `SettingsStore` for the settings window. Any change to
/// `settings` is persisted and re-applied to the running app via `onApply`.
@MainActor
final class SettingsModel: ObservableObject {
    private let store: SettingsStore
    @Published var settings: AppSettings {
        didSet { commit() }
    }
    var onApply: ((AppSettings) -> Void)?

    init(store: SettingsStore) {
        self.store = store
        self.settings = store.settings
    }

    private func commit() {
        store.update { $0 = settings }
        onApply?(settings)
    }

    /// Refresh from disk (e.g. when pause was toggled from the panel).
    func sync() {
        if settings != store.settings { settings = store.settings }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var appVersion: String
    var onExportNow: () -> Void
    var onPruneNow: () -> Void
    var onRequestAccessibility: () -> Void

    var body: some View {
        TabView {
            GeneralSettings(model: model, onRequestAccessibility: onRequestAccessibility)
                .tabItem { Label("General", systemImage: "gearshape") }
            PrivacySettings(model: model)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            RetentionSettings(model: model, onPruneNow: onPruneNow)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            ExportSettingsView(model: model, onExportNow: onExportNow)
                .tabItem { Label("Backup", systemImage: "arrow.up.doc") }
            AboutSettings(appVersion: appVersion)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 430)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var model: SettingsModel
    var onRequestAccessibility: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Launch EverClip at login", isOn: $model.settings.launchAtLogin)
                Toggle("Paste automatically after selecting", isOn: $model.settings.pasteOnSelect)
            }

            Section("Appearance") {
                Picker("Theme", selection: appearanceBinding) {
                    Text("System").tag(Appearance.system)
                    Text("Light").tag(Appearance.light)
                    Text("Dark").tag(Appearance.dark)
                }
                .pickerStyle(.segmented)
            }

            Section("Capture") {
                Stepper(value: $model.settings.pollingIntervalMilliseconds, in: 100...2000, step: 50) {
                    Text("Poll every \(model.settings.pollingIntervalMilliseconds) ms")
                }
                Stepper(value: $model.settings.topStripCount, in: 3...20) {
                    Text("Top strip shows \(model.settings.topStripCount) items")
                }
            }

            Section("Shortcut") {
                LabeledContent("Open EverClip") {
                    Text("⌥⌘V").font(.system(.body, design: .monospaced))
                }
                Toggle("Enable global shortcut", isOn: $model.settings.hotKey.isEnabled)
                Button("Grant Accessibility permission…", action: onRequestAccessibility)
                    .help("Required so EverClip can paste into other apps.")
            }
        }
        .formStyle(.grouped)
    }

    private enum Appearance { case system, light, dark }
    private var appearanceBinding: Binding<Appearance> {
        Binding(
            get: {
                switch model.settings.forcedDarkMode {
                case nil: return .system
                case .some(true): return .dark
                case .some(false): return .light
                }
            },
            set: { newValue in
                switch newValue {
                case .system: model.settings.forcedDarkMode = nil
                case .light: model.settings.forcedDarkMode = false
                case .dark: model.settings.forcedDarkMode = true
                }
            }
        )
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    @ObservedObject var model: SettingsModel
    @State private var runningApps: [RunningApp] = []

    struct RunningApp: Identifiable, Hashable {
        let id: String   // bundle id
        let name: String
    }

    var body: some View {
        Form {
            Section {
                Toggle("Pause capturing", isOn: $model.settings.isPaused)
            } footer: {
                Text("Content marked concealed or transient (e.g. by password managers) is never recorded.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Excluded apps") {
                if model.settings.excludedBundleIDs.isEmpty {
                    Text("No apps excluded.").foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(model.settings.excludedBundleIDs, id: \.self) { bundleID in
                        HStack {
                            Text(displayName(for: bundleID))
                            Spacer()
                            Button {
                                model.settings.excludedBundleIDs.removeAll { $0 == bundleID }
                            } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Menu("Add app…") {
                    ForEach(runningApps) { app in
                        Button(app.name) {
                            if !model.settings.excludedBundleIDs.contains(app.id) {
                                model.settings.excludedBundleIDs.append(app.id)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadRunningApps)
    }

    private func loadRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return RunningApp(id: id, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func displayName(for bundleID: String) -> String {
        runningApps.first(where: { $0.id == bundleID })?.name ?? bundleID
    }
}

// MARK: - Retention

private struct RetentionSettings: View {
    @ObservedObject var model: SettingsModel
    var onPruneNow: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Limit by number of items", isOn: itemsEnabled)
                if model.settings.retention.maxItems != nil {
                    Stepper(value: itemsValue, in: 100...100_000, step: 100) {
                        Text("Keep newest \(model.settings.retention.maxItems ?? 0) items")
                    }
                }
            }
            Section {
                Toggle("Limit by age", isOn: daysEnabled)
                if model.settings.retention.maxDays != nil {
                    Stepper(value: daysValue, in: 1...3650) {
                        Text("Keep items for \(model.settings.retention.maxDays ?? 0) days")
                    }
                }
            }
            Section {
                Toggle("Limit by disk size", isOn: diskEnabled)
                if model.settings.retention.maxDiskBytes != nil {
                    Stepper(value: diskMB, in: 50...100_000, step: 50) {
                        Text("Keep under \(diskMB.wrappedValue) MB")
                    }
                }
            } footer: {
                Text("Favorites are always kept and never counted against any limit.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Button("Prune now", action: onPruneNow)
            }
        }
        .formStyle(.grouped)
    }

    private var itemsEnabled: Binding<Bool> {
        Binding(get: { model.settings.retention.maxItems != nil },
                set: { model.settings.retention.maxItems = $0 ? 10_000 : nil })
    }
    private var itemsValue: Binding<Int> {
        Binding(get: { model.settings.retention.maxItems ?? 10_000 },
                set: { model.settings.retention.maxItems = $0 })
    }
    private var daysEnabled: Binding<Bool> {
        Binding(get: { model.settings.retention.maxDays != nil },
                set: { model.settings.retention.maxDays = $0 ? 90 : nil })
    }
    private var daysValue: Binding<Int> {
        Binding(get: { model.settings.retention.maxDays ?? 90 },
                set: { model.settings.retention.maxDays = $0 })
    }
    private var diskEnabled: Binding<Bool> {
        Binding(get: { model.settings.retention.maxDiskBytes != nil },
                set: { model.settings.retention.maxDiskBytes = $0 ? 2_000 * 1_000_000 : nil })
    }
    private var diskMB: Binding<Int> {
        Binding(get: { (model.settings.retention.maxDiskBytes ?? 0) / 1_000_000 },
                set: { model.settings.retention.maxDiskBytes = $0 * 1_000_000 })
    }
}

// MARK: - Export / Backup

private struct ExportSettingsView: View {
    @ObservedObject var model: SettingsModel
    var onExportNow: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Enable scheduled backups", isOn: $model.settings.export.isEnabled)
            } footer: {
                Text("Off by default. Nothing ever leaves your Mac unless you turn this on and add a destination.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if model.settings.export.isEnabled {
                Section("Schedule") {
                    Picker("Run", selection: $model.settings.export.schedule) {
                        Text("Manually only").tag(ExportSchedule.off)
                        Text("Daily").tag(ExportSchedule.daily)
                        Text("Weekly").tag(ExportSchedule.weekly)
                    }
                    Toggle("Include images & screenshots", isOn: $model.settings.export.includeBlobs)
                }

                Section("Destinations") {
                    ForEach($model.settings.export.targets) { $target in
                        TargetRow(target: $target, onRemove: {
                            model.settings.export.targets.removeAll { $0.id == target.id }
                        })
                    }

                    Menu("Add destination…") {
                        Button("Folder (or a Drive/iCloud synced folder)") { addTarget(.localFolder) }
                        Button("Google Drive (your account)") { addTarget(.googleDrive) }
                        Button("Gmail (email to yourself)") { addTarget(.gmail) }
                    }
                }

                Section {
                    Button("Back up now", action: onExportNow)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addTarget(_ kind: ExportTargetKind) {
        model.settings.export.targets.append(ExportTargetConfig(kind: kind, isEnabled: true))
    }
}

private struct TargetRow: View {
    @Binding var target: ExportTargetConfig
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(isOn: $target.isEnabled) {
                    Label(title, systemImage: symbol)
                }
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove destination")
            }

            switch target.kind {
            case .localFolder:
                HStack {
                    TextField("Folder path", text: pathBinding)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…", action: chooseFolder)
                }
            case .googleDrive:
                credentialFields
            case .gmail:
                credentialFields
                TextField("Send to (your email)", text: stringBinding(\.gmailRecipient))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        switch target.kind {
        case .localFolder: return "Folder"
        case .googleDrive: return "Google Drive"
        case .gmail: return "Gmail"
        }
    }
    private var symbol: String {
        switch target.kind {
        case .localFolder: return "folder"
        case .googleDrive: return "externaldrive.badge.icloud"
        case .gmail: return "envelope"
        }
    }

    @ViewBuilder private var credentialFields: some View {
        Text("Uses your own Google OAuth client — see the README.")
            .font(.caption2).foregroundStyle(.secondary)
        TextField("OAuth client ID", text: stringBinding(\.googleClientID))
            .textFieldStyle(.roundedBorder)
        SecureField("OAuth client secret", text: stringBinding(\.googleClientSecret))
            .textFieldStyle(.roundedBorder)
    }

    private var pathBinding: Binding<String> { stringBinding(\.localFolderPath) }

    private func stringBinding(_ keyPath: WritableKeyPath<ExportTargetConfig, String?>) -> Binding<String> {
        Binding(get: { target[keyPath: keyPath] ?? "" },
                set: { target[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            target.localFolderPath = url.path
        }
    }
}

// MARK: - About

private struct AboutSettings: View {
    var appVersion: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text("EverClip").font(.system(size: 22, weight: .semibold))
            Text("Version \(appVersion)").font(.callout).foregroundStyle(.secondary)

            Text("Your clipboard, private and permanent.\n100% local — your data never leaves your Mac unless you explicitly export it.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Link("github.com/Nihirdas/everclip", destination: URL(string: "https://github.com/Nihirdas/everclip")!)
                .font(.callout)

            Text("MIT License · © Nihir Das")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
