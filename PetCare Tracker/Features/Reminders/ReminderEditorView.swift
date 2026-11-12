import SwiftUI
import Observation

@MainActor @Observable final class ReminderEditorModel {
    var draft: ReminderDraft
    var error: String?
    var isSaving = false
    let reminder: Reminder?
    init(reminder: Reminder?, record: CareRecord?) {
        self.reminder = reminder; draft = reminder.map(ReminderDraft.init) ?? ReminderDraft()
        if reminder == nil, let record {
            draft.title = record.title
            if let date = record.appointmentAt {
                draft.startDay = CalendarDay(date).iso
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft.hour = parts.hour ?? 9; draft.minute = parts.minute ?? 0
            }
        }
    }
    func save(services: AppServices, pet: Pet, record: CareRecord?) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try services.store.saveReminder(draft, pet: pet, reminder: reminder, record: record)
            if draft.isEnabled, services.notifications.authorization == .notDetermined { await services.notifications.requestPermission() }
            await services.reconcile()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

struct ReminderEditorView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let pet: Pet
    let record: CareRecord?
    @State private var model: ReminderEditorModel
    @State private var deleting = false
    @State private var paywall = false
    init(pet: Pet, reminder: Reminder? = nil, record: CareRecord? = nil) {
        self.pet = pet; self.record = record; _model = State(initialValue: ReminderEditorModel(reminder: reminder, record: record))
    }
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Care activity") {
                    TextField("Title", text: $model.draft.title).accessibilityIdentifier("reminderTitle")
                    DayPicker(title: "First date", iso: $model.draft.startDay)
                    DatePicker("Time", selection: Binding(get: {
                        Calendar.current.date(from: DateComponents(hour: model.draft.hour, minute: model.draft.minute)) ?? Date()
                    }, set: {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                        model.draft.hour = parts.hour ?? 9; model.draft.minute = parts.minute ?? 0
                    }), displayedComponents: .hourAndMinute)
                    Picker("Repeat", selection: $model.draft.recurrence) {
                        ForEach(RepeatRule.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("reminderRepeat")
                    if model.draft.recurrence != .never {
                        // An interval saved while premium was active stays editable.
                        if services.premium.isPremium || model.draft.interval > 1 {
                            Stepper(value: $model.draft.interval, in: RepeatRule.intervals) {
                                Text(model.draft.recurrence.title(interval: model.draft.interval))
                            }.accessibilityIdentifier("reminderInterval")
                        } else {
                            Button("Set a custom interval with premium", systemImage: "repeat") { paywall = true }
                                .disabled(services.premium.isRefreshing).accessibilityIdentifier("intervalLocked")
                        }
                    }
                    Toggle("Enabled", isOn: $model.draft.isEnabled)
                }
                Section {
                    Text("Reminder times follow your current time zone. Monthly dates use the last day when needed.")
                    Text("iOS limits pending notifications. Open the app regularly to refresh upcoming reminders.")
                    Text("A denied permission keeps this reminder in the app. Enable notifications in Settings to receive alerts.")
                    InlineError(message: model.error)
                }.font(.footnote)
                if model.reminder != nil {
                    Section {
                        Button("Mark as done") {
                            guard let reminder = model.reminder else { return }
                            do { try services.store.completeReminder(reminder); dismiss() }
                            catch { model.error = error.localizedDescription }
                        }
                        Button("Delete reminder", role: .destructive) { deleting = true }
                    }
                }
            }
            .disabled(model.isSaving)
            .navigationTitle(L10n.text(model.reminder == nil ? "Add reminder" : "Edit reminder")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isSaving { ProgressView() }
                    else { Button("Save") { Task { if await model.save(services: services, pet: pet, record: record) { dismiss() } } }.accessibilityIdentifier("saveReminder") }
                }
            }
            .interactiveDismissDisabled(model.isSaving)
            .sheet(isPresented: $paywall) { PremiumView() }
            .confirmationDialog("Delete this reminder?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete reminder", role: .destructive) {
                    guard let reminder = model.reminder else { return }
                    do { try services.store.deleteReminder(reminder); dismiss() }
                    catch { model.error = error.localizedDescription }
                }
            }
        }
    }
}

struct ReminderRow: View {
    let reminder: Reminder
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reminder.title).font(.headline)
            if let due = ReminderCalendar.due(reminder.definition) {
                HStack {
                    if due < Date() { Label("Overdue", systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                    Text(due, format: .dateTime.day().month().hour().minute())
                }.font(.subheadline)
            } else { Text("Inactive").font(.subheadline).foregroundStyle(.secondary) }
            Text(reminder.recurrence.title(interval: reminder.interval)).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}

struct RemindersView: View {
    @Environment(AppServices.self) private var services
    @State private var choosingPet = false
    @State private var selectedPet: Pet?
    var body: some View {
        NavigationStack {
            Group {
                if services.store.reminders.isEmpty {
                    EmptyCareView(title: "A little help remembering", message: "Plan care activities and keep their dates in one place.", symbol: "bell", actionTitle: "Add reminder") { choosingPet = true }
                } else {
                    List {
                        Section { NotificationStatusView() }
                        ForEach(services.store.reminders.sorted {
                            (ReminderCalendar.due($0.definition) ?? .distantFuture) < (ReminderCalendar.due($1.definition) ?? .distantFuture)
                        }) { reminder in
                            if let pet = reminder.pet {
                                NavigationLink {
                                    ReminderEditorView(pet: pet, reminder: reminder)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(pet.name).font(.caption).foregroundStyle(.secondary)
                                        ReminderRow(reminder: reminder)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reminders")
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Add reminder", systemImage: "plus") { choosingPet = true } } }
            .confirmationDialog(L10n.text(services.store.pets.isEmpty ? "Add a pet first" : "Choose a pet"), isPresented: $choosingPet, titleVisibility: .visible) {
                ForEach(services.store.pets) { pet in Button(pet.name) { selectedPet = pet } }
            }
            .sheet(item: $selectedPet) { ReminderEditorView(pet: $0) }
        }
    }
}
