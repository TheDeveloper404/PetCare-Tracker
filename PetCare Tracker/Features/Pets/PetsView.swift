import SwiftUI
import Charts

struct PetsView: View {
    @Environment(AppServices.self) private var services
    @State private var adding = false
    @State private var paywall = false
    var body: some View {
        NavigationStack {
            Group {
                if services.store.pets.isEmpty {
                    EmptyCareView(title: "Meet your care companion", message: "Add your pet to start building their health history.", symbol: "pawprint", actionTitle: "Add pet") { add() }
                } else {
                    List(services.store.pets) { pet in
                        NavigationLink { PetDetailView(pet: pet) } label: { PetRow(pet: pet, photos: services.store.photos) }
                    }
                }
            }
            .navigationTitle("Pets")
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Add pet", systemImage: "plus") { add() }.disabled(services.premium.isRefreshing).accessibilityIdentifier("addPet") } }
            .sheet(isPresented: $adding) { PetEditorView() }
            .sheet(isPresented: $paywall) { PremiumView() }
        }
    }
    private func add() {
        if !services.premium.isPremium && !services.store.pets.isEmpty { paywall = true } else { adding = true }
    }
}

enum PetSheet: String, Identifiable {
    case edit, record, weight, reminder, premium
    var id: String { rawValue }
}

struct PetDetailView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @AppStorage("weightUnit") private var weightUnit = "kg"
    let pet: Pet
    @State private var sheet: PetSheet?
    @State private var selectedWeight: WeightEntry?
    @State private var filter: RecordCategory?
    @State private var search = ""
    @State private var deleting = false
    @State private var error: String?
    @State private var share: FileShare?
    @State private var exporting = false
    private var unit: WeightUnit { WeightUnit(rawValue: weightUnit) ?? .kilograms }
    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    PetAvatar(pet: pet, photos: services.store.photos, size: 80)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pet.name).font(.title2.bold())
                        Text(L10n.text(pet.species)).foregroundStyle(.secondary)
                        if !pet.breed.isEmpty { Text(pet.breed).font(.subheadline) }
                    }
                }.padding(.vertical, 8)
                if let day = pet.birthDay.flatMap({ CalendarDay(iso: $0) }) {
                    LabeledContent("Date of birth") { Text(day.date(), format: .dateTime.day().month().year()) }
                }
                if !pet.sex.isEmpty { LabeledContent("Sex", value: L10n.text(pet.sex)) }
                if !pet.microchip.isEmpty { LabeledContent("Microchip", value: pet.microchip).textSelection(.enabled) }
                if !pet.notes.isEmpty { Text(pet.notes).textSelection(.enabled) }
            }
            if !pet.vetName.isEmpty || !pet.vetPhone.isEmpty || !pet.vetAddress.isEmpty {
                Section("Veterinarian") {
                    if !pet.vetName.isEmpty { Text(pet.vetName) }
                    if !pet.vetPhone.isEmpty, let url = URL(string: "tel:" + pet.vetPhone.filter { $0.isNumber || $0 == "+" }) {
                        Link(destination: url) { Label(pet.vetPhone, systemImage: "phone") }
                    }
                    if !pet.vetAddress.isEmpty { Text(pet.vetAddress).textSelection(.enabled) }
                }
            }
            Section("Quick actions") {
                Button("Add record", systemImage: "plus.circle") { sheet = .record }.accessibilityIdentifier("addRecord")
                Button("Add reminder", systemImage: "bell.badge") { sheet = .reminder }
                Button("Add weight", systemImage: "scalemass") { sheet = .weight }
            }
            Section("Health history") {
                Picker("Category", selection: $filter) {
                    Text("All records").tag(nil as RecordCategory?)
                    ForEach(RecordCategory.allCases) { Text($0.title).tag(Optional($0)) }
                }.accessibilityIdentifier("historyCategory")
                let records = pet.records.filter {
                    (filter == nil || $0.category == filter)
                        && (search.isEmpty || $0.title.localizedStandardContains(search) || $0.notes.localizedStandardContains(search))
                }.sorted { $0.day > $1.day }
                if records.isEmpty {
                    Text(L10n.text(search.isEmpty && filter == nil ? "No records yet. Add your first care record." : "No matching records.")).foregroundStyle(.secondary)
                }
                ForEach(records) { record in
                    NavigationLink { RecordDetailView(record: record) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(record.title, systemImage: record.category.symbol)
                            if let day = CalendarDay(iso: record.day) { Text(day.date(), format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            Section("Weight history") {
                if pet.weights.isEmpty { Text("No measurements yet.").foregroundStyle(.secondary) }
                if pet.weights.count >= 2, !services.premium.isPremium {
                    Button("See the weight chart with premium", systemImage: "chart.xyaxis.line") { sheet = .premium }
                        .disabled(services.premium.isRefreshing).accessibilityIdentifier("weightChartLocked")
                }
                if pet.weights.count >= 2, services.premium.isPremium {
                    Chart(pet.weights.sorted { $0.day < $1.day }) { entry in
                        if let day = CalendarDay(iso: entry.day) {
                            LineMark(x: .value("Date", day.date()), y: .value("Weight", unit.display(entry.kilograms)))
                            PointMark(x: .value("Date", day.date()), y: .value("Weight", unit.display(entry.kilograms)))
                        }
                    }
                    .foregroundStyle(CareTheme.tint)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 180).padding(.vertical, 8)
                    .accessibilityLabel("Weight chart").accessibilityIdentifier("weightChart")
                }
                ForEach(pet.weights.sorted { $0.day > $1.day }) { entry in
                    Button { selectedWeight = entry } label: {
                        LabeledContent {
                            Text(unit.display(entry.kilograms), format: .number.precision(.fractionLength(0...2))) + Text(" " + unit.rawValue)
                        } label: {
                            if let day = CalendarDay(iso: entry.day) { Text(day.date(), format: .dateTime.day().month().year()) }
                        }
                    }.foregroundStyle(.primary)
                }
            }
            Section("Reminders") {
                if pet.reminders.isEmpty { Text("No reminders yet.").foregroundStyle(.secondary) }
                ForEach(pet.reminders) { reminder in
                    NavigationLink { ReminderEditorView(pet: pet, reminder: reminder) } label: { ReminderRow(reminder: reminder) }
                }
            }
            Section {
                Button { exportPDF() } label: {
                    if exporting { ProgressView() } else { Label("Export health PDF", systemImage: "square.and.arrow.up") }
                }.disabled(exporting || services.premium.isRefreshing)
                Button("Delete pet", role: .destructive) { deleting = true }
                InlineError(message: error)
            }
        }
        .navigationTitle(pet.name).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search records")
        .toolbar { Button("Edit") { sheet = .edit }.accessibilityIdentifier("editPet") }
        .sheet(item: $sheet) { value in
            switch value {
            case .edit: PetEditorView(pet: pet)
            case .record: RecordEditorView(pet: pet)
            case .weight: WeightEditorView(pet: pet, unit: unit, locale: locale)
            case .reminder: ReminderEditorView(pet: pet)
            case .premium: PremiumView()
            }
        }
        .sheet(item: $selectedWeight) { WeightEditorView(pet: pet, entry: $0, unit: unit, locale: locale) }
        .sheet(item: $share) { ActivitySheet(url: $0.url) }
        .confirmationDialog("Delete this pet and all their records, reminders and photos?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete pet", role: .destructive) {
                do { try services.store.deletePet(pet); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        }
    }
    private func exportPDF() {
        guard services.premium.isPremium else { sheet = .premium; return }
        exporting = true
        Task {
            defer { exporting = false }
            do { share = FileShare(url: try await PDFExporter.export(pet: pet, unit: unit, premium: services.premium.isPremium)) }
            catch { self.error = CareError.export.localizedDescription }
        }
    }
}
