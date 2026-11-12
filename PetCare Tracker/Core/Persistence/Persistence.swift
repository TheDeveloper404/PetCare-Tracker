import Foundation
import SwiftData
import Observation

enum Persistence {
    static func container(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PetCareSchemaV1.self)
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        let container = try ModelContainer(for: schema, migrationPlan: PetCareMigrationPlan.self, configurations: [configuration])
        container.mainContext.autosaveEnabled = false
        return container
    }
}

struct PetDraft {
    var name = ""
    var species = "Dog"
    var breed = ""
    var birthDay: String?
    var sex = ""
    var microchip = ""
    var notes = ""
    var vetName = ""
    var vetPhone = ""
    var vetAddress = ""
    var photoData: Data?
    var removePhoto = false
    init() {}
    init(_ pet: Pet) {
        name = pet.name; species = pet.species; breed = pet.breed; birthDay = pet.birthDay
        sex = pet.sex; microchip = pet.microchip; notes = pet.notes
        vetName = pet.vetName; vetPhone = pet.vetPhone; vetAddress = pet.vetAddress
    }
}

struct RecordDraft {
    var category: RecordCategory = .vaccination
    var title = ""
    var day = CalendarDay(Date()).iso
    var notes = ""
    var appointmentAt = Date()
    init() {}
    init(_ record: CareRecord) {
        category = record.category; title = record.title; day = record.day; notes = record.notes
        appointmentAt = record.appointmentAt ?? Date()
    }
}

struct ReminderDraft {
    var title = ""
    var startDay = CalendarDay(Date()).iso
    var hour = 9
    var minute = 0
    var recurrence: RepeatRule = .never
    var interval = 1
    var isEnabled = true
    init() {}
    init(_ reminder: Reminder) {
        title = reminder.title; startDay = reminder.startDay; hour = reminder.hour; minute = reminder.minute
        recurrence = reminder.recurrence; interval = reminder.interval; isEnabled = reminder.isEnabled
    }
}

/// The single mutation boundary. Views edit value drafts, never live persisted objects.
@MainActor @Observable final class CareStore {
    let container: ModelContainer
    let photos: PhotoStore
    private(set) var pets: [Pet] = []
    private(set) var records: [CareRecord] = []
    private(set) var reminders: [Reminder] = []
    private(set) var weights: [WeightEntry] = []
    private(set) var revision = 0
    var readError: String?
    @ObservationIgnored var saveOperation: (ModelContext) throws -> Void = { try $0.save() }
    @ObservationIgnored var backupImportWorker: BackupImportWorker?

    init(container: ModelContainer, photos: PhotoStore) throws {
        self.container = container; self.photos = photos
        try reload()
    }
    var context: ModelContext { container.mainContext }
    func reload() throws {
        let newPets = try context.fetch(FetchDescriptor<Pet>(sortBy: [SortDescriptor(\Pet.name)]))
        let newRecords = try context.fetch(FetchDescriptor<CareRecord>(sortBy: [SortDescriptor(\CareRecord.day, order: .reverse)]))
        let newReminders = try context.fetch(FetchDescriptor<Reminder>())
        let newWeights = try context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\WeightEntry.day, order: .reverse)]))
        pets = newPets; records = newRecords; reminders = newReminders; weights = newWeights
        revision += 1; readError = nil
    }
    func refresh() {
        do { try reload() } catch { readError = L10n.text("Your data could not be loaded. Please try again.") }
    }
    private func commit() throws {
        do { try saveOperation(context) }
        catch { context.rollback(); throw CareError.persistence }
        // A fetch failure after commit must not be reported as a failed save.
        refresh()
    }

    @discardableResult func savePet(_ draft: PetDraft, pet: Pet? = nil, premium: Bool) throws -> Pet {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CareError.nameRequired }
        guard pet != nil || premium || pets.isEmpty else { throw CareError.premiumRequired }
        if let birth = draft.birthDay {
            guard CalendarDay(iso: birth) != nil, birth <= CalendarDay(Date()).iso else { throw CareError.invalidDate }
        }
        let oldPhoto = pet?.photoName
        let newPhoto = try draft.photoData.map { try photos.save($0) }
        let value = pet ?? Pet(name: name, species: draft.species)
        if pet == nil { context.insert(value) }
        value.name = name; value.species = draft.species; value.breed = draft.breed
        value.birthDay = draft.birthDay; value.sex = draft.sex; value.microchip = draft.microchip; value.notes = draft.notes
        value.vetName = draft.vetName.trimmingCharacters(in: .whitespacesAndNewlines)
        value.vetPhone = draft.vetPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        value.vetAddress = draft.vetAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if let newPhoto { value.photoName = newPhoto }
        else if draft.removePhoto { value.photoName = nil }
        do { try commit() }
        catch { if let newPhoto { photos.remove(newPhoto) }; throw error }
        if oldPhoto != value.photoName, let oldPhoto { photos.remove(oldPhoto) }
        return value
    }

    func deletePet(_ pet: Pet) throws {
        let photo = pet.photoName
        context.delete(pet); try commit()
        if let photo { photos.remove(photo) }
    }

    @discardableResult func saveRecord(_ draft: RecordDraft, pet: Pet, record: CareRecord? = nil) throws -> CareRecord {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw CareError.titleRequired }
        guard CalendarDay(iso: draft.day) != nil else { throw CareError.invalidDate }
        let value = record ?? CareRecord(pet: pet, category: draft.category, title: title, day: draft.day)
        if record == nil { context.insert(value) }
        if value.category == .appointment,
           draft.category != .appointment || value.appointmentAt != draft.appointmentAt {
            for reminder in value.reminders { reminder.isEnabled = false }
        }
        value.categoryRaw = draft.category.rawValue; value.title = title
        value.day = draft.category == .appointment ? CalendarDay(draft.appointmentAt).iso : draft.day
        value.notes = draft.notes
        value.appointmentAt = draft.category == .appointment ? draft.appointmentAt : nil
        try commit(); return value
    }
    func deleteRecord(_ record: CareRecord) throws { context.delete(record); try commit() }

    @discardableResult func saveReminder(_ draft: ReminderDraft, pet: Pet, reminder: Reminder? = nil, record: CareRecord? = nil) throws -> Reminder {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw CareError.titleRequired }
        guard CalendarDay(iso: draft.startDay) != nil, (0...23).contains(draft.hour), (0...59).contains(draft.minute),
              RepeatRule.intervals.contains(draft.interval) else { throw CareError.invalidDate }
        let interval = draft.recurrence == .never ? 1 : draft.interval
        let value = reminder ?? Reminder(pet: pet, title: title, startDay: draft.startDay, hour: draft.hour, minute: draft.minute)
        if reminder == nil { context.insert(value) }
        let changed = value.startDay != draft.startDay || value.hour != draft.hour || value.minute != draft.minute || value.recurrenceRaw != draft.recurrence.rawValue || value.interval != interval
        if changed || (!value.isEnabled && draft.isEnabled && draft.recurrence == .never) {
            value.completedThrough = nil
        }
        value.title = title; value.startDay = draft.startDay; value.hour = draft.hour; value.minute = draft.minute
        value.recurrenceRaw = draft.recurrence.rawValue; value.interval = interval; value.isEnabled = draft.isEnabled
        if let record { value.record = record }
        try commit(); return value
    }
    func completeReminder(_ reminder: Reminder, now: Date = Date()) throws {
        reminder.completedThrough = max(now, ReminderCalendar.due(reminder.definition) ?? now)
        if reminder.recurrence == .never { reminder.isEnabled = false }
        try commit()
    }
    func deleteReminder(_ reminder: Reminder) throws { context.delete(reminder); try commit() }

    func saveWeight(pet: Pet, day: String, kilograms: Double, notes: String, entry: WeightEntry? = nil) throws {
        guard kilograms.isFinite, kilograms > 0 else { throw CareError.invalidWeight }
        guard CalendarDay(iso: day) != nil else { throw CareError.invalidDate }
        let value = entry ?? WeightEntry(pet: pet, day: day, kilograms: kilograms, notes: notes)
        if entry == nil { context.insert(value) }
        value.day = day; value.kilograms = kilograms; value.notes = notes
        try commit()
    }
    func deleteWeight(_ entry: WeightEntry) throws { context.delete(entry); try commit() }
}
