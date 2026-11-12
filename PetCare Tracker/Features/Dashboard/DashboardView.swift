import SwiftUI
import Observation

@MainActor @Observable final class DashboardModel {
    let store: CareStore
    init(store: CareStore) { self.store = store }
    func overdue(now: Date) -> [Reminder] {
        store.reminders.filter { ReminderCalendar.due($0.definition).map { $0 < now } ?? false }
            .sorted { (ReminderCalendar.due($0.definition) ?? .distantFuture) < (ReminderCalendar.due($1.definition) ?? .distantFuture) }
    }
    func upcoming(now: Date) -> [Reminder] {
        store.reminders.filter { ReminderCalendar.due($0.definition).map { $0 >= now } ?? false }
            .sorted { (ReminderCalendar.due($0.definition) ?? .distantFuture) < (ReminderCalendar.due($1.definition) ?? .distantFuture) }
    }
    func appointments(now: Date) -> [CareRecord] {
        store.records.filter { $0.category == .appointment && ($0.appointmentAt ?? .distantPast) >= now }
            .sorted { ($0.appointmentAt ?? .distantFuture) < ($1.appointmentAt ?? .distantFuture) }
    }
    func recent(now: Date) -> [CareRecord] {
        Array(store.records.filter { $0.day <= CalendarDay(now).iso }.prefix(5))
    }
}

struct DashboardView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.locale) private var locale
    @AppStorage("weightUnit") private var weightUnit = "kg"
    @State private var addingPet = false
    @State private var quickAction: QuickAction?
    @State private var selectedSheet: QuickActionSheet?
    private enum QuickAction { case record, reminder, weight }
    private struct QuickActionSheet: Identifiable {
        let pet: Pet
        let action: QuickAction
        var id: UUID { pet.id }
    }
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let model = DashboardModel(store: services.store)
                let now = timeline.date
                Group {
                    if services.store.pets.isEmpty {
                        EmptyCareView(title: "Care, all in one place", message: "Keep health records, plan routines and remember the next little thing.", symbol: "heart.text.square", actionTitle: "Add your first pet") { addingPet = true }
                    } else {
                        List {
                            Section("Quick actions") {
                                Button("Add record", systemImage: "plus.circle") { add(.record) }
                                    .accessibilityIdentifier("dashboardAddRecord")
                                Button("Add reminder", systemImage: "bell.badge") { add(.reminder) }
                                    .accessibilityIdentifier("dashboardAddReminder")
                                Button("Add weight", systemImage: "scalemass") { add(.weight) }
                                    .accessibilityIdentifier("dashboardAddWeight")
                            }
                            Section("Your companions") {
                                ForEach(services.store.pets) { pet in
                                    NavigationLink { PetDetailView(pet: pet) } label: { PetRow(pet: pet, photos: services.store.photos) }
                                }
                            }
                            if !model.overdue(now: now).isEmpty {
                                Section("Needs attention") {
                                    ForEach(model.overdue(now: now)) { item in
                                        if let pet = item.pet { NavigationLink { ReminderEditorView(pet: pet, reminder: item) } label: { ReminderRow(reminder: item) } }
                                    }
                                }
                            }
                            Section("Coming up") {
                                if model.upcoming(now: now).isEmpty && model.appointments(now: now).isEmpty {
                                    Label("No upcoming activities", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                                }
                                ForEach(model.upcoming(now: now)) { item in
                                    if let pet = item.pet {
                                        NavigationLink { ReminderEditorView(pet: pet, reminder: item) } label: {
                                            VStack(alignment: .leading) { Text(pet.name).font(.caption).foregroundStyle(.secondary); ReminderRow(reminder: item) }
                                        }
                                    }
                                }
                                ForEach(model.appointments(now: now)) { item in
                                    NavigationLink { RecordDetailView(record: item) } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Label(item.title, systemImage: "calendar")
                                            if let date = item.appointmentAt { Text(date, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary) }
                                        }
                                    }
                                }
                            }
                            Section("Recent records") {
                                if model.recent(now: now).isEmpty { Text("No records yet. Add your first care record.").foregroundStyle(.secondary) }
                                ForEach(model.recent(now: now)) { record in
                                    NavigationLink { RecordDetailView(record: record) } label: { Label(record.title, systemImage: record.category.symbol) }
                                }
                            }
                            Section { NotificationStatusView() }
                        }
                    }
                }
            }
            .navigationTitle("Today")
            .sheet(isPresented: $addingPet) { PetEditorView() }
            .confirmationDialog("Choose a pet", isPresented: Binding(get: { quickAction != nil }, set: {
                if !$0 { quickAction = nil }
            }), titleVisibility: .visible, presenting: quickAction) { action in
                ForEach(services.store.pets) { pet in
                    Button(pet.name) { selectedSheet = QuickActionSheet(pet: pet, action: action) }
                }
            }
            .sheet(item: $selectedSheet) { selection in
                switch selection.action {
                case .record: RecordEditorView(pet: selection.pet)
                case .reminder: ReminderEditorView(pet: selection.pet)
                case .weight: WeightEditorView(pet: selection.pet, unit: WeightUnit(rawValue: weightUnit) ?? .kilograms, locale: locale)
                }
            }
        }
    }
    private func add(_ action: QuickAction) {
        if services.store.pets.count == 1, let pet = services.store.pets.first {
            selectedSheet = QuickActionSheet(pet: pet, action: action)
        } else { quickAction = action }
    }
}
