import XCTest
import UserNotifications
import SwiftData
import PDFKit
import UIKit
import zlib
@testable import PetCare_Tracker

@MainActor final class FakeNotifications: NotificationClient {
    var status: UNAuthorizationStatus = .authorized
    var requests: [String: ScheduledCare] = [:]
    var fail = false
    func authorization() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool { status == .authorized }
    func pendingIdentifiers() async -> [String] { Array(requests.keys) }
    func remove(_ identifiers: [String]) { for id in identifiers { requests[id] = nil } }
    func removeDelivered(except reminderIDs: Set<UUID>) async {}
    func add(_ item: ScheduledCare, timeZone: TimeZone) async throws {
        if fail { throw CareError.persistence }; requests[item.identifier] = item
    }
}

@MainActor final class NotificationTests: XCTestCase {
    let zone = TimeZone(secondsFromGMT: 0)!
    func item(id: UUID = UUID(), repeatRule: RepeatRule = .daily) -> ReminderDefinition {
        ReminderDefinition(id: id, title: "Care", petName: "Milo", startDay: "2026-01-01", hour: 9, minute: 0, recurrence: repeatRule)
    }
    // "Respect iOS pending-notification limits."
    func testQueueIsBoundedSortedAndDeduplicated() {
        let value = item()
        let now = CalendarDay(iso: "2026-01-01")!.date(timeZone: zone)
        let plan = NotificationPlan.build([value, value, item()], now: now, timeZone: zone)
        XCTAssertEqual(plan.count, 64)
        XCTAssertEqual(Set(plan.map(\.identifier)).count, 64)
        XCTAssertEqual(plan.map(\.date), plan.map(\.date).sorted())
    }
    // "Respect iOS pending-notification limits."
    func testOtherPendingRequestsArePreservedAndCountTowardsCapacity() async {
        let client = FakeNotifications()
        client.requests["unrelated"] = ScheduledCare(reminderID: UUID(), date: Date(), title: "")
        let scheduler = NotificationScheduler(client: client)
        await scheduler.reconcile([item()])
        XCTAssertNotNil(client.requests["unrelated"])
        XCTAssertEqual(scheduler.scheduledCount, 63)
        XCTAssertEqual(client.requests.count, 64)
    }
    // "Update or cancel pending notifications when records change."
    func testReconcileIsIdempotentAndDeletionCancels() async {
        let client = FakeNotifications(), value = item()
        let scheduler = NotificationScheduler(client: client)
        let now = CalendarDay(iso: "2026-01-01")!.date(timeZone: zone)
        await scheduler.reconcile([value], now: now, timeZone: zone)
        let identifiers = Set(client.requests.keys)
        await scheduler.reconcile([value], now: now, timeZone: zone)
        XCTAssertEqual(Set(client.requests.keys), identifiers)
        await scheduler.reconcile([], now: now, timeZone: zone)
        XCTAssertTrue(client.requests.isEmpty)
    }
    // "Handle notification permission denial gracefully."
    func testDeniedPermissionDoesNotScheduleAndRetryRecovers() async {
        let client = FakeNotifications(); client.status = .denied
        let scheduler = NotificationScheduler(client: client)
        await scheduler.reconcile([item()])
        XCTAssertEqual(scheduler.authorization, .denied)
        XCTAssertTrue(client.requests.isEmpty)
        client.status = .authorized; client.fail = true
        await scheduler.reconcile([item()])
        XCTAssertNotNil(scheduler.error)
        client.fail = false
        await scheduler.reconcile([item()])
        XCTAssertNil(scheduler.error)
        XCTAssertEqual(client.requests.count, 64)
    }
    // "Handle time zones, daylight saving changes, and calendar edge cases."
    func testMissingAndRepeatedDSTTimesAreDeterministic() {
        let timeZone = TimeZone(identifier: "America/New_York")!
        let spring = ReminderDefinition(id: UUID(), title: "Care", petName: "", startDay: "2026-03-08", hour: 2, minute: 30, recurrence: .daily)
        let autumn = ReminderDefinition(id: UUID(), title: "Care", petName: "", startDay: "2026-11-01", hour: 1, minute: 30, recurrence: .daily)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let missing = ReminderCalendar.occurrence(spring, index: 0, timeZone: timeZone)!
        XCTAssertEqual(calendar.component(.hour, from: missing), 3)
        let repeated = ReminderCalendar.occurrence(autumn, index: 0, timeZone: timeZone)!
        XCTAssertEqual(timeZone.secondsFromGMT(for: repeated), -4 * 3600)
    }
}

@MainActor final class FakePurchases: PurchaseProvider {
    let changes = AsyncStream<Void> { _ in }
    var entitled = false
    var outcome: PurchaseOutcome = .purchased
    var failure = false
    var restoreCalls = 0
    var pendingChecks: [CheckedContinuation<Bool, Never>] = []
    var suspendChecks = false
    func product() async throws -> PremiumProduct? { PremiumProduct(id: "test", displayPrice: "€6.99") }
    func purchase() async throws -> PurchaseOutcome {
        if failure { throw CareError.verification }
        if case .purchased = outcome { entitled = true }
        return outcome
    }
    func restore() async throws { restoreCalls += 1; if failure { throw CareError.purchaseUnavailable } }
    func hasEntitlement() async throws -> Bool {
        if suspendChecks { return await withCheckedContinuation { pendingChecks.append($0) } }
        if failure { throw CareError.verification }; return entitled
    }
}

@MainActor final class PremiumTests: XCTestCase {
    // "Handle refunds and revoked entitlements."
    func testOlderEntitlementRefreshCannotOverrideNewerRevocation() async {
        let provider = FakePurchases(); provider.suspendChecks = true
        let model = PremiumStore(provider: provider)
        let first = Task { await model.refresh() }
        while provider.pendingChecks.count < 1 { await Task.yield() }
        let second = Task { await model.refresh() }
        while provider.pendingChecks.count < 2 { await Task.yield() }
        provider.pendingChecks[1].resume(returning: false)
        await second.value
        provider.pendingChecks[0].resume(returning: true)
        await first.value
        XCTAssertFalse(model.isPremium)
        XCTAssertFalse(model.isRefreshing)
    }
    // "Verify transactions."
    func testEntitlementPolicyRejectsUnverifiedWrongTypeWrongProductAndRevoked() {
        XCTAssertTrue(EntitlementPolicy.grants(productID: "premium", expectedID: "premium", verified: true, nonConsumable: true, revoked: false))
        XCTAssertFalse(EntitlementPolicy.grants(productID: "premium", expectedID: "premium", verified: false, nonConsumable: true, revoked: false))
        XCTAssertFalse(EntitlementPolicy.grants(productID: "other", expectedID: "premium", verified: true, nonConsumable: true, revoked: false))
        XCTAssertFalse(EntitlementPolicy.grants(productID: "premium", expectedID: "premium", verified: true, nonConsumable: false, revoked: false))
        XCTAssertFalse(EntitlementPolicy.grants(productID: "premium", expectedID: "premium", verified: true, nonConsumable: true, revoked: true))
    }
    // "Restore purchases." / "Handle refunds and revoked entitlements."
    func testPurchaseRestoreAndRevocation() async {
        let provider = FakePurchases(), model = PremiumStore(provider: FakePurchases())
        await model.refresh(); XCTAssertFalse(model.isPremium)
        let store = PremiumStore(provider: provider)
        await store.loadProduct(); XCTAssertEqual(store.product?.displayPrice, "€6.99")
        await store.purchase(); XCTAssertTrue(store.isPremium)
        await store.restore(); XCTAssertTrue(store.isPremium)
        XCTAssertEqual(provider.restoreCalls, 1)
        provider.entitled = false
        await store.refresh(); XCTAssertFalse(store.isPremium)
    }
    // "Never delete existing pet data if premium access is lost."
    func testPendingCancelledAndUnverifiedDoNotGrantAccess() async {
        let provider = FakePurchases(), store = PremiumStore(provider: FakePurchases())
        await store.refresh(); XCTAssertFalse(store.isPremium)
        let pending = PremiumStore(provider: provider)
        provider.outcome = .pending
        await pending.purchase(); XCTAssertFalse(pending.isPremium); XCTAssertNotNil(pending.message)
        provider.outcome = .cancelled
        await pending.purchase(); XCTAssertFalse(pending.isPremium)
        provider.failure = true
        await pending.purchase(); XCTAssertFalse(pending.isPremium); XCTAssertNotNil(pending.message)
    }
}

@MainActor final class BackupTests: XCTestCase {
    var directory: URL!
    var store: CareStore!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try CareStore(container: Persistence.container(inMemory: true), photos: PhotoStore(directory: directory))
    }
    override func tearDownWithError() throws {
        store = nil; try FileManager.default.removeItem(at: directory)
    }
    func populated() throws -> Pet {
        var draft = PetDraft(); draft.name = "Milo"; draft.microchip = "123456"; draft.notes = "Notes"
        draft.birthDay = "2024-02-29"
        draft.photoData = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        let pet = try store.savePet(draft, premium: false)
        var record = RecordDraft(); record.title = "Visit"
        let saved = try store.saveRecord(record, pet: pet)
        var reminder = ReminderDraft(); reminder.title = "Care"; reminder.recurrence = .monthly
        try store.saveReminder(reminder, pet: pet, record: saved)
        try store.saveWeight(pet: pet, day: "2026-11-03", kilograms: 4.2, notes: "Healthy")
        return pet
    }
    // "Implement local data export and import/restore where practical."
    func testRoundTripPhotosRelationshipsAndDuplicateImport() async throws {
        let pet = try populated(), service = BackupService(store: store)
        let archive = try BackupService.decode(BackupService.encode(service.snapshot()))
        let petID = pet.id
        try store.deletePet(pet)
        let imported = try await service.importArchive(archive, premium: false)
        XCTAssertEqual(imported, ImportResult(imported: 1, skipped: 0))
        XCTAssertEqual(store.pets.first?.id, petID)
        XCTAssertEqual(store.records.first?.pet?.id, petID)
        XCTAssertEqual(store.reminders.first?.record?.id, store.records.first?.id)
        XCTAssertEqual(store.weights.first?.kilograms, 4.2)
        XCTAssertNotNil(try store.photos.data(for: store.pets.first?.photoName))
        let duplicate = try await service.importArchive(archive, premium: false)
        XCTAssertEqual(duplicate, ImportResult(imported: 0, skipped: 1))
        XCTAssertEqual(store.pets.count, 1)
    }
    // "No silent data loss."
    func testFailedImportRemovesOnlyNewPhotosAndPreservesExistingPets() async throws {
        let pet = try populated()
        let service = BackupService(store: store), archive = try service.snapshot()
        try store.deletePet(pet)
        var other = PetDraft(); other.name = "Existing"
        try store.savePet(other, premium: false)
        service.saveOperation = { _ in throw CareError.persistence }
        do { _ = try await service.importArchive(archive, premium: true); XCTFail("Failed save must roll back import.") } catch {}
        try store.reload()
        XCTAssertEqual(store.pets.map(\.name), ["Existing"])
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
    // "No silent data loss."
    func testMalformedDuplicateAndForeignRelationshipArchivesAreRejected() throws {
        _ = try populated()
        let snapshot = try BackupService(store: store).snapshot()
        XCTAssertThrowsError(try BackupService.decode(Data("invalid".utf8)))
        var duplicate = snapshot; duplicate.pets += snapshot.pets
        XCTAssertThrowsError(try BackupService.validate(duplicate))
        var version = snapshot; version.version = 2
        XCTAssertThrowsError(try BackupService.validate(version))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: BackupService.encode(snapshot)) as? [String: Any])
        var pets = try XCTUnwrap(object["pets"] as? [[String: Any]])
        var reminders = try XCTUnwrap(pets[0]["reminders"] as? [[String: Any]])
        reminders[0]["recordID"] = UUID().uuidString
        pets[0]["reminders"] = reminders; object["pets"] = pets
        XCTAssertThrowsError(try BackupService.decode(JSONSerialization.data(withJSONObject: object)))
        XCTAssertEqual(store.pets.count, 1)
    }

    // "Import adds missing pet profiles. Existing profiles and their history are never overwritten."
    func testBackupRecoveryPreservesExistingEditsAndRestoresMultiplePetsWithPremium() async throws {
        let first = try populated()
        var secondDraft = PetDraft(); secondDraft.name = "Luna"
        let second = try store.savePet(secondDraft, premium: true)
        let service = BackupService(store: store), archive = try service.snapshot()
        var edited = PetDraft(first); edited.name = "Keep my local edit"
        try store.savePet(edited, pet: first, premium: false)
        try store.deletePet(second)
        let result = try await service.importArchive(archive, premium: true)
        XCTAssertEqual(result, ImportResult(imported: 1, skipped: 1))
        XCTAssertEqual(store.pets.count, 2)
        XCTAssertTrue(store.pets.contains { $0.name == "Keep my local edit" })
    }

    // "Pet profiles created manually | Free 1 | Premium Unlimited" (docs/APPLICATION.md) — import must not exceed it.
    func testFreeImportCannotExceedOnePetProfile() async throws {
        let first = try populated()
        var secondDraft = PetDraft(); secondDraft.name = "Luna"
        let second = try store.savePet(secondDraft, premium: true)
        let service = BackupService(store: store), archive = try service.snapshot()
        // Already at the limit with nothing new to add: allowed, nothing changes.
        try store.deletePet(second)
        var onlyFirst = archive; onlyFirst.pets.removeAll { $0.id == second.id }
        let unchanged = try await service.importArchive(onlyFirst, premium: false)
        XCTAssertEqual(unchanged, ImportResult(imported: 0, skipped: 1))
        // One existing pet plus one new pet.
        do { _ = try await service.importArchive(archive, premium: false); XCTFail("Free import must not add a second pet.") }
        catch { XCTAssertEqual(error as? CareError, .importPremiumRequired) }
        XCTAssertEqual(store.pets.map(\.name), ["Milo"])
        // Deleting the local pet first does not unlock a two-pet archive.
        try store.deletePet(first)
        do { _ = try await service.importArchive(archive, premium: false); XCTFail("Free import must not add two pets.") }
        catch { XCTAssertEqual(error as? CareError, .importPremiumRequired) }
        XCTAssertTrue(store.pets.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        // A single-pet archive into an empty store is ordinary recovery.
        let recovered = try await service.importArchive(onlyFirst, premium: false)
        XCTAssertEqual(recovered, ImportResult(imported: 1, skipped: 0))
        XCTAssertEqual(store.pets.count, 1)
    }

    // "Backup: campuri optionale (lipsa = 1, fisierele vechi raman valide; valori in afara 1...12 resping arhiva); PDF: linie de contact" (approved plan)
    func testVeterinarianAndIntervalSurviveBackupAndOlderArchivesStayValid() async throws {
        let pet = try populated()
        var draft = PetDraft(pet); draft.vetName = "Happy Paws"; draft.vetPhone = "+40 21 555 0142"; draft.vetAddress = "1 Main St"
        try store.savePet(draft, pet: pet, premium: false)
        var reminder = ReminderDraft(store.reminders[0]); reminder.interval = 3
        try store.saveReminder(reminder, pet: pet, reminder: store.reminders[0])
        XCTAssertTrue(PDFExporter.snapshot(pet: pet, unit: .kilograms).identification.contains("Veterinarian: Happy Paws, +40 21 555 0142, 1 Main St"))
        let service = BackupService(store: store)
        let data = try BackupService.encode(service.snapshot())
        try store.deletePet(pet)
        _ = try await service.importArchive(BackupService.decode(data), premium: false)
        XCTAssertEqual(store.pets.first?.vetName, "Happy Paws")
        XCTAssertEqual(store.pets.first?.vetPhone, "+40 21 555 0142")
        XCTAssertEqual(store.pets.first?.vetAddress, "1 Main St")
        XCTAssertEqual(store.reminders.first?.interval, 3)
        // The same archive as written before these fields existed.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var pets = try XCTUnwrap(object["pets"] as? [[String: Any]])
        var reminders = try XCTUnwrap(pets[0]["reminders"] as? [[String: Any]])
        for key in ["vetName", "vetPhone", "vetAddress"] { pets[0].removeValue(forKey: key) }
        reminders[0].removeValue(forKey: "interval")
        pets[0]["reminders"] = reminders; object["pets"] = pets
        let older = try BackupService.decode(JSONSerialization.data(withJSONObject: object))
        try store.deletePet(try XCTUnwrap(store.pets.first))
        _ = try await service.importArchive(older, premium: false)
        XCTAssertEqual(store.pets.first?.vetName, "")
        XCTAssertEqual(store.reminders.first?.interval, 1)
        reminders[0]["interval"] = 13
        pets[0]["reminders"] = reminders; object["pets"] = pets
        XCTAssertThrowsError(try BackupService.decode(JSONSerialization.data(withJSONObject: object)))
    }

    // Review fix: "performImport clears error but not result" and the rejected import uses its own message.
    func testFailedImportClearsThePreviousResultAndExplainsTheLimit() async throws {
        let first = try populated()
        var secondDraft = PetDraft(); secondDraft.name = "Luna"
        let second = try store.savePet(secondDraft, premium: true)
        let archive = try BackupService(store: store).snapshot()
        try store.deletePet(second)
        var onlyFirst = archive; onlyFirst.pets.removeAll { $0.id == second.id }
        let model = SettingsModel()
        await model.performImport(onlyFirst, store: store, premium: false)
        XCTAssertEqual(model.result, ImportResult(imported: 0, skipped: 1))
        XCTAssertNil(model.error)
        await model.performImport(archive, store: store, premium: false)
        XCTAssertNil(model.result)
        XCTAssertEqual(model.error, "Premium is required to import more than one pet profile.")
        XCTAssertEqual(store.pets.map(\.id), [first.id])
    }
    // Review fix: "a free user whose vet data was saved earlier cannot edit or clear it".
    func testSavedVeterinarianStaysEditableInTheEditor() throws {
        var draft = PetDraft(); draft.name = "Milo"
        let pet = try store.savePet(draft, premium: false)
        XCTAssertFalse(PetEditorModel(pet: nil).hasSavedVeterinarian)
        XCTAssertFalse(PetEditorModel(pet: pet).hasSavedVeterinarian)
        draft.vetPhone = "0215550142"
        try store.savePet(draft, pet: pet, premium: false)
        XCTAssertTrue(PetEditorModel(pet: pet).hasSavedVeterinarian)
    }

    // "rejects images over 100 megapixels before decoding" (PhotoStore.maximumPixels)
    func testOversizedImageDimensionsAreRejectedBeforeDecoding() throws {
        func png(side: Int) throws -> Data {
            func chunk(_ type: String, _ body: Data) -> Data {
                var data = withUnsafeBytes(of: UInt32(body.count).bigEndian) { Data($0) }
                let typed = Data(type.utf8) + body
                data.append(typed)
                let sum = typed.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(typed.count)) }
                withUnsafeBytes(of: UInt32(sum).bigEndian) { data.append(contentsOf: $0) }
                return data
            }
            // 1-bit grayscale rows of zeros: a few kilobytes on disk for any side length.
            let raw = Data(count: (1 + (side + 7) / 8) * side)
            var stream = Data([0x78, 0x01]) + (try (raw as NSData).compressed(using: .zlib) as Data)
            let adler = raw.withUnsafeBytes { adler32(1, $0.bindMemory(to: Bytef.self).baseAddress, uInt(raw.count)) }
            withUnsafeBytes(of: UInt32(adler).bigEndian) { stream.append(contentsOf: $0) }
            var header = Data()
            for value in [UInt32(side), UInt32(side)] { withUnsafeBytes(of: value.bigEndian) { header.append(contentsOf: $0) } }
            header.append(contentsOf: [1, 0, 0, 0, 0])
            return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + chunk("IHDR", header) + chunk("IDAT", stream) + chunk("IEND", Data())
        }
        // The same generator yields a valid image at a normal size, so the rejection below is the size limit.
        let accepted = try store.photos.save(png(side: 256))
        store.photos.remove(accepted)
        XCTAssertThrowsError(try store.photos.save(png(side: 10_001))) { XCTAssertEqual($0 as? CareError, .photo) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    // "PDF export" is included in "Premium lifetime".
    func testPDFExportIsGatedWithoutDeletingData() async throws {
        let pet = try populated()
        do { _ = try await PDFExporter.export(pet: pet, unit: .kilograms, premium: false); XCTFail("Free access must not export a PDF.") }
        catch { XCTAssertEqual(error as? CareError, .premiumRequired) }
        XCTAssertEqual(store.pets.count, 1)
        let url = try await PDFExporter.export(pet: pet, unit: .pounds, premium: true)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNotNil(PDFDocument(url: url))
    }

    // "import in fundal cu limita explicita de 64 MB"
    func testOversizedFileIsRejectedBeforeReadingItsContents() async throws {
        _ = try populated()
        let url = directory.appendingPathComponent("oversized.json")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(BackupService.maximumBytes + 1))
        try handle.close()
        let model = SettingsModel()
        await model.read(url: url)
        XCTAssertEqual(model.error, CareError.backupTooLarge.localizedDescription)
        XCTAssertNil(model.pendingArchive)
        XCTAssertFalse(model.isWorking)
        XCTAssertEqual(store.pets.count, 1)
    }

    // "import in fundal" / "No silent data loss."
    func testImportSaveRunsOffMainThread() async throws {
        let pet = try populated(), service = BackupService(store: store)
        let archive = try service.snapshot()
        try store.deletePet(pet)
        service.saveOperation = { context in
            XCTAssertFalse(Thread.isMainThread)
            try context.save()
        }
        let result = try await service.importArchive(archive, premium: false)
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(store.pets.count, 1)
    }
    // "Existing profiles and their history are never overwritten."
    func testConcurrentImportsSerializeWithoutDuplicateProfiles() async throws {
        let pet = try populated(), service = BackupService(store: store)
        let archive = try service.snapshot()
        try store.deletePet(pet)
        let other = BackupService(store: store)
        async let first = service.importArchive(archive, premium: false)
        async let second = other.importArchive(archive, premium: false)
        let results = try await [first, second]
        XCTAssertEqual(results.map(\.imported).sorted(), [0, 1])
        XCTAssertEqual(store.pets.count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    }
    // "Generate a clean, readable PDF" / "Relevant notes"
    func testPDFPaginatesLongNotesWithoutTruncation() throws {
        let value = PDFHealthSnapshot(name: "Milo", identification: ["Cat"], sections: [("Notes", [String(repeating: "Long care history. ", count: 1800) + "END-OF-HISTORY"])])
        let data = PDFExporter.render(value)
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(document.pageCount, 1)
        XCTAssertTrue(document.string?.contains("END-OF-HISTORY") == true)
        XCTAssertTrue(document.string?.contains("Not a certified veterinary document") == true)
    }
}
