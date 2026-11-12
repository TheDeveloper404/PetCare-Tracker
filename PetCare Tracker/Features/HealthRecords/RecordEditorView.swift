import SwiftUI
import Observation

@MainActor @Observable final class RecordEditorModel {
    var draft: RecordDraft
    var error: String?
    var didPauseReminders = false
    let record: CareRecord?
    init(record: CareRecord?, category: RecordCategory) {
        self.record = record; draft = record.map(RecordDraft.init) ?? RecordDraft()
        if record == nil { draft.category = category }
    }
    func save(store: CareStore, pet: Pet) -> Bool {
        do {
            let hadEnabledReminders = record?.reminders.contains(where: \.isEnabled) ?? false
            let saved = try store.saveRecord(draft, pet: pet, record: record)
            didPauseReminders = hadEnabledReminders && saved.reminders.allSatisfy { !$0.isEnabled }
            return true
        }
        catch { self.error = error.localizedDescription; return false }
    }
}

struct RecordEditorView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let pet: Pet
    @State private var model: RecordEditorModel
    init(pet: Pet, record: CareRecord? = nil, category: RecordCategory = .vaccination) {
        self.pet = pet; _model = State(initialValue: RecordEditorModel(record: record, category: category))
    }
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Details") {
                    Picker("Category", selection: $model.draft.category) {
                        ForEach(RecordCategory.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("recordCategory")
                    TextField("Title", text: $model.draft.title).accessibilityIdentifier("recordTitle")
                    if model.draft.category == .appointment {
                        DatePicker("Appointment date", selection: $model.draft.appointmentAt)
                            .accessibilityIdentifier("appointmentDate")
                            .onChange(of: model.draft.appointmentAt) { _, value in model.draft.day = CalendarDay(value).iso }
                    } else { DayPicker(title: "Date", iso: $model.draft.day) }
                    TextField("Notes", text: $model.draft.notes, axis: .vertical).lineLimit(3...8)
                }
                if model.error != nil { Section { InlineError(message: model.error) } }
            }
            .navigationTitle(L10n.text(model.record == nil ? "Add record" : "Edit record"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.save(store: services.store, pet: pet), !model.didPauseReminders { dismiss() }
                    }.accessibilityIdentifier("saveRecord")
                }
            }
            .alert("Associated reminders paused", isPresented: $model.didPauseReminders) {
                Button("Done") { dismiss() }
            } message: {
                Text("The appointment date changed. Open Reminders to review the dates and enable its reminders again.")
            }
        }
    }
}

struct RecordDetailView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let record: CareRecord
    @State private var editing = false
    @State private var addingReminder = false
    @State private var deleting = false
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Label(record.category.title, systemImage: record.category.symbol).foregroundStyle(CareTheme.tint)
                if let date = record.appointmentAt { Text(date, format: .dateTime.day().month().year().hour().minute()) }
                else if let day = CalendarDay(iso: record.day) { Text(day.date(), format: .dateTime.day().month().year()) }
                if !record.notes.isEmpty { Text(record.notes).textSelection(.enabled) }
            }
            Section("Reminders") {
                ForEach(record.reminders) { item in ReminderRow(reminder: item) }
                Button("Add reminder", systemImage: "bell.badge") { addingReminder = true }
            }
            Section {
                Button("Edit record") { editing = true }
                Button("Delete record", role: .destructive) { deleting = true }
                InlineError(message: error)
            }
        }
        .navigationTitle(record.title).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) { if let pet = record.pet { RecordEditorView(pet: pet, record: record) } }
        .sheet(isPresented: $addingReminder) { if let pet = record.pet { ReminderEditorView(pet: pet, record: record) } }
        .confirmationDialog("Delete this record and its reminders?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete record", role: .destructive) {
                do { try services.store.deleteRecord(record); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        }
    }
}
