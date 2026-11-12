import SwiftUI
import UniformTypeIdentifiers
import Observation

@MainActor @Observable final class SettingsModel {
    var isWorking = false
    var error: String?
    var result: ImportResult?
    var pendingArchive: BackupArchive?
    var share: FileShare?
    func export(store: CareStore) async {
        guard !isWorking else { return }
        isWorking = true; error = nil
        defer { isWorking = false }
        do {
            let archive = try BackupService(store: store).snapshot()
            let url = try await Task.detached(priority: .userInitiated) {
                try ExportFiles.write(BackupService.encode(archive), extension: "json")
            }.value
            share = FileShare(url: url)
        } catch { self.error = (error as? CareError ?? .export).localizedDescription }
    }
    func read(url: URL) async {
        isWorking = true; error = nil
        defer { isWorking = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { pendingArchive = try await Task.detached(priority: .userInitiated) { try BackupService.readArchive(url) }.value }
        catch { self.error = (error as? CareError ?? .backup).localizedDescription }
    }
    func performImport(_ archive: BackupArchive, store: CareStore, premium: Bool) async {
        isWorking = true; error = nil; result = nil
        defer { isWorking = false; pendingArchive = nil }
        do { result = try await BackupService(store: store).importArchive(archive, premium: premium) }
        catch { self.error = (error as? CareError ?? .backup).localizedDescription }
    }
}

struct NotificationStatusView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch services.notifications.authorization {
            case .denied:
                Label("Notifications are off", systemImage: "bell.slash")
                Button("Open notification settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
            case .notDetermined:
                Label("Alerts are optional", systemImage: "bell")
                Text("Notification permission is requested when you save an enabled reminder.").font(.footnote).foregroundStyle(.secondary)
            default:
                Label("Notifications enabled", systemImage: "bell.badge")
                LabeledContent("Scheduled alerts", value: services.notifications.scheduledCount.formatted())
                if let date = services.notifications.scheduledThrough {
                    LabeledContent("Scheduled through") { Text(date, format: .dateTime.day().month().year()) }
                }
            }
            InlineError(message: services.notifications.error)
        }
    }
}

struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @AppStorage("appLanguage") private var language = "system"
    @AppStorage("weightUnit") private var unit = "kg"
    @State private var model = SettingsModel()
    @State private var importing = false
    @State private var premium = false
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Preferences") {
                    Picker("Language", selection: $language) {
                        Text("System language").tag("system")
                        Text("English").tag("en")
                        Text("Română").tag("ro")
                    }
                    Picker("Weight unit", selection: $unit) {
                        Text("Kilograms (kg)").tag("kg")
                        Text("Pounds (lb)").tag("lb")
                    }
                }
                Section("Notifications") {
                    NotificationStatusView()
                    Text("iOS limits pending notifications. Open the app regularly to refresh upcoming reminders.").font(.footnote)
                    Text("Notification delivery depends on your device settings. This app does not provide medical advice.").font(.footnote)
                    Button("Refresh reminders") { Task { await services.reconcile() } }
                }
                Section("Your data") {
                    Button("Export full backup", systemImage: "square.and.arrow.up") { Task { await model.export(store: services.store) } }
                    Button("Import backup", systemImage: "square.and.arrow.down") { importing = true }
                        .disabled(services.premium.isRefreshing)
                    Text("Backups contain all pet records and photos. Files are not encrypted. Store and share them carefully.").font(.footnote)
                    Text("Import adds missing pet profiles. Existing profiles and their history are never overwritten.").font(.footnote)
                    Text("Backups must be 64 MB or smaller.").font(.footnote)
                    Text("Data stays on this device. There is no cloud sync or guaranteed cloud backup. Deleting the app may remove its data. Export backups regularly.").font(.footnote)
                    if model.isWorking { ProgressView("Preparing your data") }
                    InlineError(message: model.error)
                    if let result = model.result {
                        LabeledContent("Imported pets", value: result.imported.formatted())
                        LabeledContent("Existing pets skipped", value: result.skipped.formatted())
                    }
                }.disabled(model.isWorking)
                Section("Premium") {
                    Button { premium = true } label: { Label(L10n.text(services.premium.isPremium ? "Premium is active" : "Explore lifetime premium"), systemImage: "pawprint.circle") }
                }
                Section("About") {
                    LabeledContent("Pet Care Tracker", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    Text("No accounts. No ads. No tracking.").font(.footnote)
                    Text("Owner-maintained records. Not a certified veterinary document.").font(.footnote)
                }
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): Task { await model.read(url: url) }
                case .failure: model.error = L10n.text("The file could not be opened. Please try again.")
                }
            }
            .confirmationDialog("Import this backup? Existing profiles will be skipped.", isPresented: Binding(get: { model.pendingArchive != nil }, set: { if !$0 { model.pendingArchive = nil } }), titleVisibility: .visible) {
                Button("Import backup") {
                    if let archive = model.pendingArchive { Task { await model.performImport(archive, store: services.store, premium: services.premium.isPremium) } }
                }
                Button("Cancel", role: .cancel) { model.pendingArchive = nil }
            }
            .sheet(item: $model.share) { ActivitySheet(url: $0.url) }
            .sheet(isPresented: $premium) { PremiumView() }
        }
    }
}
