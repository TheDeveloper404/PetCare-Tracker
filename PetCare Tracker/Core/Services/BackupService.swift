import Foundation
import SwiftData
import ImageIO
import Dispatch

nonisolated struct BackupArchive: Codable, Sendable {
    var version = 1
    var exportedAt: Date = Date()
    var pets: [PetBackup]
}
nonisolated struct PetBackup: Codable, Sendable {
    let id: UUID
    let name: String
    let species: String
    let breed: String
    let birthDay: String?
    let sex: String
    let microchip: String
    let notes: String
    let photo: Data?
    // Optional so archives exported before these fields existed stay valid.
    let vetName: String?
    let vetPhone: String?
    let vetAddress: String?
    let records: [RecordBackup]
    let reminders: [ReminderBackup]
    let weights: [WeightBackup]
}
nonisolated struct RecordBackup: Codable, Sendable {
    let id: UUID
    let category: RecordCategory
    let title: String
    let day: String
    let notes: String
    let appointmentAt: Date?
}
nonisolated struct ReminderBackup: Codable, Sendable {
    let id: UUID
    let recordID: UUID?
    let title: String
    let startDay: String
    let hour: Int
    let minute: Int
    let recurrence: RepeatRule
    let isEnabled: Bool
    let completedThrough: Date?
    let interval: Int?
}
nonisolated struct WeightBackup: Codable, Sendable {
    let id: UUID
    let day: String
    let kilograms: Double
    let notes: String
}
nonisolated struct ImportResult: Equatable, Sendable {
    let imported: Int
    let skipped: Int
}

@MainActor final class BackupService {
    let store: CareStore
    var saveOperation: @Sendable (ModelContext) throws -> Void = { try $0.save() }
    init(store: CareStore) { self.store = store }
    func snapshot() throws -> BackupArchive {
        guard store.readError == nil else { throw CareError.export }
        return try BackupArchive(pets: store.pets.map { pet in
            PetBackup(id: pet.id, name: pet.name, species: pet.species, breed: pet.breed, birthDay: pet.birthDay,
                sex: pet.sex, microchip: pet.microchip, notes: pet.notes, photo: try store.photos.data(for: pet.photoName),
                vetName: pet.vetName, vetPhone: pet.vetPhone, vetAddress: pet.vetAddress,
                records: pet.records.map { RecordBackup(id: $0.id, category: $0.category, title: $0.title, day: $0.day, notes: $0.notes, appointmentAt: $0.appointmentAt) },
                reminders: pet.reminders.map { ReminderBackup(id: $0.id, recordID: $0.record?.id, title: $0.title, startDay: $0.startDay,
                    hour: $0.hour, minute: $0.minute, recurrence: $0.recurrence, isEnabled: $0.isEnabled, completedThrough: $0.completedThrough, interval: $0.interval) },
                weights: pet.weights.map { WeightBackup(id: $0.id, day: $0.day, kilograms: $0.kilograms, notes: $0.notes) })
        })
    }
    nonisolated static func encode(_ archive: BackupArchive) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)
        guard data.count <= maximumBytes else { throw CareError.backupTooLarge }
        return data
    }
    nonisolated static func decode(_ data: Data) throws -> BackupArchive {
        guard data.count <= maximumBytes else { throw CareError.backupTooLarge }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        do { let archive = try decoder.decode(BackupArchive.self, from: data); try validate(archive); return archive }
        catch { throw CareError.backup }
    }
    nonisolated static func validate(_ archive: BackupArchive) throws {
        guard archive.version == 1, archive.exportedAt.timeIntervalSince1970.isFinite else { throw CareError.backup }
        var pets = Set<UUID>(), records = Set<UUID>(), reminders = Set<UUID>(), weights = Set<UUID>()
        for pet in archive.pets {
            guard pets.insert(pet.id).inserted, !pet.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  pet.birthDay.map({ CalendarDay(iso: $0) != nil }) ?? true else { throw CareError.backup }
            if let photo = pet.photo {
                guard let source = CGImageSourceCreateWithData(photo as CFData, nil), CGImageSourceGetCount(source) > 0 else { throw CareError.backup }
            }
            let recordIDs = Set(pet.records.map(\.id))
            for record in pet.records {
                guard records.insert(record.id).inserted, !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      CalendarDay(iso: record.day) != nil,
                      (record.category == .appointment) == (record.appointmentAt != nil) else { throw CareError.backup }
            }
            for reminder in pet.reminders {
                guard reminders.insert(reminder.id).inserted, !reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      CalendarDay(iso: reminder.startDay) != nil, (0...23).contains(reminder.hour),
                      (0...59).contains(reminder.minute), reminder.recordID.map({ recordIDs.contains($0) }) ?? true,
                      reminder.interval.map({ RepeatRule.intervals.contains($0) }) ?? true else { throw CareError.backup }
            }
            for weight in pet.weights {
                guard weights.insert(weight.id).inserted, CalendarDay(iso: weight.day) != nil,
                      weight.kilograms.isFinite, weight.kilograms > 0 else { throw CareError.backup }
            }
        }
    }

    nonisolated static let maximumBytes = 64 * 1024 * 1024

    nonisolated static func readArchive(_ url: URL) throws -> BackupArchive {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try handle.seekToEnd() <= UInt64(maximumBytes) else { throw CareError.backupTooLarge }
        try handle.seek(toOffset: 0)
        var data = Data()
        while let chunk = try handle.read(upToCount: min(1024 * 1024, maximumBytes - data.count + 1)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= maximumBytes else { throw CareError.backupTooLarge }
        }
        return try decode(data)
    }

    func importArchive(_ archive: BackupArchive, premium: Bool) async throws -> ImportResult {
        let container = store.container
        if store.backupImportWorker == nil {
            store.backupImportWorker = BackupImportWorker(container: container)
        }
        let worker = store.backupImportWorker!
        let result = try await worker.apply(archive, premium: premium, photos: store.photos, saveOperation: saveOperation)
        store.refresh()
        return result
    }
}

nonisolated final class BackupImportWorker: Sendable {
    private let container: ModelContainer
    private let queue = DispatchQueue(label: "PetCareTracker.BackupImport", qos: .userInitiated)
    init(container: ModelContainer) { self.container = container }

    func apply(_ archive: BackupArchive, premium: Bool, photos: PhotoStore,
               saveOperation: @escaping @Sendable (ModelContext) throws -> Void) async throws -> ImportResult {
        let container = self.container
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result {
                    try BackupService.validate(archive)
                    let context = ModelContext(container); context.autosaveEnabled = false
                    let existingPets = Set(try context.fetch(FetchDescriptor<Pet>()).map(\.id))
                    let imported = archive.pets.filter { !existingPets.contains($0.id) }
                    // Recovery cannot exceed the free profile limit; premium is checked before any write.
                    guard premium || imported.isEmpty || existingPets.count + imported.count <= 1 else { throw CareError.importPremiumRequired }
                    let existingRecords = Set(try context.fetch(FetchDescriptor<CareRecord>()).map(\.id))
                    let existingReminders = Set(try context.fetch(FetchDescriptor<Reminder>()).map(\.id))
                    let existingWeights = Set(try context.fetch(FetchDescriptor<WeightEntry>()).map(\.id))
                    for pet in imported {
                        guard existingRecords.isDisjoint(with: pet.records.map(\.id)),
                              existingReminders.isDisjoint(with: pet.reminders.map(\.id)),
                              existingWeights.isDisjoint(with: pet.weights.map(\.id)) else { throw CareError.backup }
                    }
                    var writtenPhotos: [String] = []
                    do {
                        for item in imported {
                            let pet = Pet(id: item.id, name: item.name, species: item.species)
                            pet.breed = item.breed; pet.birthDay = item.birthDay; pet.sex = item.sex; pet.microchip = item.microchip; pet.notes = item.notes
                            pet.vetName = item.vetName ?? ""; pet.vetPhone = item.vetPhone ?? ""; pet.vetAddress = item.vetAddress ?? ""
                            if let data = item.photo {
                                let name = try photos.save(data); writtenPhotos.append(name); pet.photoName = name
                            }
                            context.insert(pet)
                            var recordMap: [UUID: CareRecord] = [:]
                            for value in item.records {
                                let record = CareRecord(id: value.id, pet: pet, category: value.category, title: value.title,
                                                        day: value.day, notes: value.notes, appointmentAt: value.appointmentAt)
                                context.insert(record); recordMap[value.id] = record
                            }
                            for value in item.reminders {
                                let reminder = Reminder(id: value.id, pet: pet, title: value.title, startDay: value.startDay,
                                    hour: value.hour, minute: value.minute, recurrence: value.recurrence, record: value.recordID.flatMap { recordMap[$0] })
                                reminder.isEnabled = value.isEnabled; reminder.completedThrough = value.completedThrough
                                reminder.interval = value.interval ?? 1
                                context.insert(reminder)
                            }
                            for value in item.weights {
                                context.insert(WeightEntry(id: value.id, pet: pet, day: value.day, kilograms: value.kilograms, notes: value.notes))
                            }
                        }
                        try saveOperation(context)
                    } catch {
                        context.rollback()
                        for name in writtenPhotos { photos.remove(name) }
                        throw CareError.backup
                    }
                    return ImportResult(imported: imported.count, skipped: archive.pets.count - imported.count)
                })
            }
        }
    }
}

nonisolated enum ExportFiles {
    static func write(_ data: Data, extension fileExtension: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PetCareExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let url = directory.appendingPathComponent("PetCare-" + UUID().uuidString).appendingPathExtension(fileExtension)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }
}
