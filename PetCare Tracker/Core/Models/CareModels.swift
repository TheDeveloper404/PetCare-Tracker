import Foundation
import SwiftData

nonisolated enum PetCareSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Pet.self, CareRecord.self, Reminder.self, WeightEntry.self]
    }

    @Model nonisolated final class Pet {
        @Attribute(.unique) var id: UUID
        var name: String
        var species: String
        var breed: String
        var birthDay: String?
        var sex: String
        var microchip: String
        var notes: String
        var photoName: String?
        var vetName: String = ""
        var vetPhone: String = ""
        var vetAddress: String = ""
        @Relationship(deleteRule: .cascade, inverse: \CareRecord.pet) var records: [CareRecord] = []
        @Relationship(deleteRule: .cascade, inverse: \Reminder.pet) var reminders: [Reminder] = []
        @Relationship(deleteRule: .cascade, inverse: \WeightEntry.pet) var weights: [WeightEntry] = []

        init(id: UUID = UUID(), name: String, species: String) {
            self.id = id; self.name = name; self.species = species
            breed = ""; sex = ""; microchip = ""; notes = ""
        }
    }

    @Model nonisolated final class CareRecord {
        @Attribute(.unique) var id: UUID
        var pet: Pet?
        var categoryRaw: String
        var title: String
        var day: String
        var notes: String
        var appointmentAt: Date?
        @Relationship(deleteRule: .cascade, inverse: \Reminder.record) var reminders: [Reminder] = []

        init(id: UUID = UUID(), pet: Pet, category: RecordCategory, title: String, day: String, notes: String = "", appointmentAt: Date? = nil) {
            self.id = id; self.pet = pet; categoryRaw = category.rawValue
            self.title = title; self.day = day; self.notes = notes; self.appointmentAt = appointmentAt
        }
        var category: RecordCategory { RecordCategory(rawValue: categoryRaw) ?? .note }
    }

    @Model nonisolated final class Reminder {
        @Attribute(.unique) var id: UUID
        var pet: Pet?
        var record: CareRecord?
        var title: String
        var startDay: String
        var hour: Int
        var minute: Int
        var recurrenceRaw: String
        var isEnabled: Bool
        var completedThrough: Date?
        var interval: Int = 1

        init(id: UUID = UUID(), pet: Pet, title: String, startDay: String, hour: Int, minute: Int, recurrence: RepeatRule = .never, record: CareRecord? = nil) {
            self.id = id; self.pet = pet; self.title = title; self.startDay = startDay
            self.hour = hour; self.minute = minute; recurrenceRaw = recurrence.rawValue
            self.record = record; isEnabled = true
        }
        var recurrence: RepeatRule { RepeatRule(rawValue: recurrenceRaw) ?? .never }
        var definition: ReminderDefinition {
            ReminderDefinition(id: id, title: title, petName: pet?.name ?? "", startDay: startDay,
                               hour: hour, minute: minute, recurrence: recurrence,
                               isEnabled: isEnabled && pet != nil, completedThrough: completedThrough, interval: interval)
        }
    }

    @Model nonisolated final class WeightEntry {
        @Attribute(.unique) var id: UUID
        var pet: Pet?
        var day: String
        var kilograms: Double
        var notes: String

        init(id: UUID = UUID(), pet: Pet, day: String, kilograms: Double, notes: String = "") {
            self.id = id; self.pet = pet; self.day = day; self.kilograms = kilograms; self.notes = notes
        }
    }
}

typealias Pet = PetCareSchemaV1.Pet
typealias CareRecord = PetCareSchemaV1.CareRecord
typealias Reminder = PetCareSchemaV1.Reminder
typealias WeightEntry = PetCareSchemaV1.WeightEntry

enum PetCareMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PetCareSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

nonisolated enum RecordCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case vaccination = "Vaccination", parasite = "Parasite treatment", medication = "Medication"
    case veterinary = "Veterinary visit", appointment = "Appointment", note = "Care note"
    var id: String { rawValue }
    var title: String { L10n.text(rawValue) }
    var symbol: String {
        switch self {
        case .vaccination: return "syringe"
        case .parasite: return "shield.lefthalf.filled"
        case .medication: return "pills"
        case .veterinary: return "cross.case"
        case .appointment: return "calendar"
        case .note: return "note.text"
        }
    }
}

nonisolated enum RepeatRule: String, Codable, CaseIterable, Identifiable, Sendable {
    case never = "Does not repeat", daily = "Daily", weekly = "Weekly", monthly = "Monthly", yearly = "Yearly"
    var id: String { rawValue }
    var title: String { L10n.text(rawValue) }
    static let intervals = 1...12
    /// "Monthly" for every occurrence, "Every 3 months" for a custom interval.
    func title(interval: Int) -> String {
        let format: String
        switch self {
        case .never: return title
        case .daily: format = "Every %lld days"
        case .weekly: format = "Every %lld weeks"
        case .monthly: format = "Every %lld months"
        case .yearly: format = "Every %lld years"
        }
        return interval <= 1 ? title : String(format: L10n.text(format), interval)
    }
}

nonisolated enum WeightUnit: String, CaseIterable, Identifiable, Sendable {
    case kilograms = "kg", pounds = "lb"
    var id: String { rawValue }
    func display(_ kg: Double) -> Double { self == .kilograms ? kg : kg * 2.2046226218 }
    func canonical(_ value: Double) -> Double { self == .kilograms ? value : value / 2.2046226218 }
}
