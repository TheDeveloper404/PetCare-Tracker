import SwiftUI
import Observation

@MainActor @Observable final class WeightEditorModel {
    var day: String
    var value: String
    var notes: String
    var error: String?
    let entry: WeightEntry?
    let locale: Locale
    init(entry: WeightEntry?, unit: WeightUnit, locale: Locale) {
        self.locale = locale
        self.entry = entry; day = entry?.day ?? CalendarDay(Date()).iso
        value = entry.map { unit.display($0.kilograms).formatted(.number.grouping(.never).precision(.significantDigits(1...17)).locale(locale)) } ?? ""
        notes = entry?.notes ?? ""
    }
    func save(store: CareStore, pet: Pet, unit: WeightUnit) -> Bool {
        do {
            let scanner = Scanner(string: value)
            scanner.locale = locale
            guard let number = scanner.scanDouble(), scanner.isAtEnd else { throw CareError.invalidWeight }
            try store.saveWeight(pet: pet, day: day, kilograms: unit.canonical(number), notes: notes, entry: entry)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

struct WeightEditorView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let pet: Pet
    let unit: WeightUnit
    @State private var model: WeightEditorModel
    @State private var deleting = false
    init(pet: Pet, entry: WeightEntry? = nil, unit: WeightUnit, locale: Locale) {
        self.pet = pet; self.unit = unit
        _model = State(initialValue: WeightEditorModel(entry: entry, unit: unit, locale: locale))
    }
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    LabeledContent(L10n.text("Weight") + " (" + unit.rawValue + ")") {
                        TextField("Weight", text: $model.value)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("weightValue")
                    }
                    DayPicker(title: "Date", iso: $model.day)
                    TextField("Notes", text: $model.notes, axis: .vertical)
                    InlineError(message: model.error)
                }
                if model.entry != nil { Button("Delete measurement", role: .destructive) { deleting = true } }
            }
            .navigationTitle(L10n.text(model.entry == nil ? "Add weight" : "Edit weight")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if model.save(store: services.store, pet: pet, unit: unit) { dismiss() } }
                }
            }
            .confirmationDialog("Delete this measurement?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete measurement", role: .destructive) {
                    guard let entry = model.entry else { return }
                    do { try services.store.deleteWeight(entry); dismiss() } catch { model.error = error.localizedDescription }
                }
            }
        }
    }
}
