import XCTest
import SwiftData
@testable import PetCare_Tracker

@MainActor final class PersistenceTests: XCTestCase {
    var directory: URL!
    var store: CareStore!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try CareStore(container: Persistence.container(inMemory: true), photos: PhotoStore(directory: directory))
    }
    override func tearDownWithError() throws {
        store = nil
        try FileManager.default.removeItem(at: directory)
    }
    // "Users can create and manage multiple pet profiles."
    func testCRUDAndCascade() throws {
        var draft = PetDraft(); draft.name = "Milo"
        let pet = try store.savePet(draft, premium: false)
        draft.name = "Milo edited"
        try store.savePet(draft, pet: pet, premium: false)
        XCTAssertEqual(store.pets.first?.name, "Milo edited")
        var record = RecordDraft(); record.title = "Vaccination"
        let saved = try store.saveRecord(record, pet: pet)
        record.notes = "Updated"
        try store.saveRecord(record, pet: pet, record: saved)
        XCTAssertEqual(store.records.first?.notes, "Updated")
        var reminder = ReminderDraft(); reminder.title = "Follow up"
        try store.saveReminder(reminder, pet: pet, record: saved)
        try store.saveWeight(pet: pet, day: "2026-11-03", kilograms: 4.2, notes: "")
        try store.deleteRecord(saved)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertTrue(store.reminders.isEmpty)
        try store.saveReminder(reminder, pet: pet)
        try store.deletePet(pet)
        XCTAssertTrue(store.pets.isEmpty)
        XCTAssertTrue(store.weights.isEmpty)
        XCTAssertTrue(store.reminders.isEmpty)
    }
    // "Free: One pet profile"
    func testPremiumLimitDoesNotBlockExistingData() throws {
        var draft = PetDraft(); draft.name = "Milo"
        let first = try store.savePet(draft, premium: false)
        draft.name = "Luna"
        XCTAssertThrowsError(try store.savePet(draft, premium: false))
        try store.savePet(draft, premium: true)
        try store.savePet(draft, pet: first, premium: false)
        XCTAssertEqual(store.pets.count, 2)
    }
    // "No silent data loss."
    func testFailedSaveRollsBack() throws {
        var draft = PetDraft(); draft.name = "Original"
        let pet = try store.savePet(draft, premium: false)
        store.saveOperation = { _ in throw CareError.persistence }
        draft.name = "Changed"
        XCTAssertThrowsError(try store.savePet(draft, pet: pet, premium: false))
        XCTAssertEqual(pet.name, "Original")
        XCTAssertThrowsError(try store.savePet(draft, premium: true))
        store.saveOperation = { try $0.save() }
        try store.reload()
        XCTAssertEqual(store.pets.count, 1)
    }
    // "Data survives application restarts."
    func testDiskReopen() throws {
        let url = directory.appendingPathComponent("test.store")
        var first: CareStore? = try CareStore(container: Persistence.container(url: url), photos: store.photos)
        var draft = PetDraft(); draft.name = "Survives restart"
        try first!.savePet(draft, premium: false)
        first = nil
        let reopened = try CareStore(container: Persistence.container(url: url), photos: store.photos)
        XCTAssertEqual(reopened.pets.first?.name, "Survives restart")
    }
    // "Weight measurements" / "Allow users to: Add records Edit records Delete records"
    func testWeightEditingAndDeletionUsesCanonicalKilograms() throws {
        var draft = PetDraft(); draft.name = "Milo"
        let pet = try store.savePet(draft, premium: false)
        try store.saveWeight(pet: pet, day: "2026-11-03", kilograms: WeightUnit.pounds.canonical(10), notes: "")
        let entry = try XCTUnwrap(store.weights.first)
        XCTAssertEqual(WeightUnit.pounds.display(entry.kilograms), 10, accuracy: 0.00001)
        try store.saveWeight(pet: pet, day: "2026-11-04", kilograms: 5, notes: "Updated", entry: entry)
        XCTAssertEqual(store.weights.first?.notes, "Updated")
        XCTAssertEqual(store.weights.count, 1)
        XCTAssertThrowsError(try store.saveWeight(pet: pet, day: "2026-11-04", kilograms: .nan, notes: ""))
        try store.deleteWeight(entry)
        XCTAssertTrue(store.weights.isEmpty)
    }
    // "conversia completa, conform limbii, la salvare, cu teste EN/RO"
    func testWeightEditorSavesAndEditsLocalizedDecimals() throws {
        var draft = PetDraft(); draft.name = "Milo"
        let pet = try store.savePet(draft, premium: false)
        for (language, input) in [("en", "4.7"), ("ro", "4,7")] {
            let locale = Locale(identifier: language)
            let model = WeightEditorModel(entry: nil, unit: .kilograms, locale: locale)
            model.value = input; model.notes = language
            XCTAssertTrue(model.save(store: store, pet: pet, unit: .kilograms))
            let entry = try XCTUnwrap(store.weights.first { $0.notes == language })
            XCTAssertEqual(entry.kilograms, 4.7, accuracy: 0.000001)
            let edit = WeightEditorModel(entry: entry, unit: .kilograms, locale: locale)
            XCTAssertEqual(edit.value, input)
            edit.value = language == "en" ? "5.25" : "5,25"
            XCTAssertTrue(edit.save(store: store, pet: pet, unit: .kilograms))
            XCTAssertEqual(entry.kilograms, 5.25, accuracy: 0.000001)
        }
    }

    // "No silent data loss." / "pastrarea preciziei greutatii la editare (EN/RO si lb)"
    func testWeightEditorPreservesPrecisionWhenOnlyNotesChange() throws {
        var draft = PetDraft(); draft.name = "Milo"
        let pet = try store.savePet(draft, premium: false)
        for kilograms in [4.123456789, 0.00000000123456789] {
            for language in ["en", "ro"] {
                for unit in WeightUnit.allCases {
                    try store.saveWeight(pet: pet, day: "2026-11-04", kilograms: kilograms, notes: "Original")
                    let entry = try XCTUnwrap(store.weights.first { $0.notes == "Original" })
                    let model = WeightEditorModel(entry: entry, unit: unit, locale: Locale(identifier: language))
                    model.notes = "Notes only"
                    XCTAssertTrue(model.save(store: store, pet: pet, unit: unit))
                    // Conversion to/from pounds can differ by a floating-point ULP, not by formatting precision.
                    XCTAssertEqual(entry.kilograms, kilograms, accuracy: kilograms.ulp * 2)
                    XCTAssertEqual(entry.notes, "Notes only")
                    try store.deleteWeight(entry)
                }
            }
        }
    }

    // "conversia completa, conform limbii, la salvare, cu teste EN/RO"
    func testWeightEditorRejectsPartialNumbersWithoutChangingStoredWeight() throws {
        var draft = PetDraft(); draft.name = "Milo"
        let pet = try store.savePet(draft, premium: false)
        try store.saveWeight(pet: pet, day: "2026-11-04", kilograms: 4.7, notes: "Original")
        let entry = try XCTUnwrap(store.weights.first)
        for (language, invalid) in [("en", "4,7"), ("en", "4.7.2"), ("en", "4junk"), ("ro", "4.7"), ("ro", "4,7junk"), ("ro", ""), ("en", "0"), ("en", "-2")] {
            let model = WeightEditorModel(entry: entry, unit: .kilograms, locale: Locale(identifier: language))
            model.value = invalid
            XCTAssertFalse(model.save(store: store, pet: pet, unit: .kilograms), "Unexpectedly accepted \(language): \(invalid)")
            XCTAssertNotNil(model.error)
            XCTAssertEqual(entry.kilograms, 4.7, accuracy: 0.000001)
            XCTAssertEqual(store.weights.count, 1)
        }
    }

    // "Support configurable reminder dates." / "Support recurring reminders where appropriate."
    func testReminderEditingAndCompletion() throws {
        var draft = PetDraft(); draft.name = "Milo"
        let pet = try store.savePet(draft, premium: false)
        var reminder = ReminderDraft(); reminder.title = "Care"; reminder.startDay = "2026-01-31"; reminder.recurrence = .monthly
        let saved = try store.saveReminder(reminder, pet: pet)
        try store.completeReminder(saved, now: CalendarDay(iso: "2026-02-01")!.date())
        XCTAssertEqual(CalendarDay(ReminderCalendar.due(saved.definition)!).iso, "2026-02-28")
        reminder.startDay = "2026-03-15"
        try store.saveReminder(reminder, pet: pet, reminder: saved)
        XCTAssertNil(saved.completedThrough)
        XCTAssertEqual(CalendarDay(ReminderCalendar.due(saved.definition)!).iso, "2026-03-15")
        reminder.isEnabled = false
        try store.saveReminder(reminder, pet: pet, reminder: saved)
        XCTAssertNil(ReminderCalendar.due(saved.definition))
    }
    // "Reminder.interval: every N days/weeks/months/years, N between 1 and 12, on top of the existing repeat rule." (docs/APPLICATION.md)
    func testCustomIntervalsMultiplyTheRepeatRule() {
        let zone = TimeZone(identifier: "Europe/Bucharest")!
        func days(_ start: String, _ rule: RepeatRule, _ interval: Int) -> [String] {
            let item = ReminderDefinition(id: UUID(), title: "Care", petName: "Milo", startDay: start, hour: 9, minute: 0, recurrence: rule, interval: interval)
            return (0...2).map { CalendarDay(ReminderCalendar.occurrence(item, index: $0, timeZone: zone)!, timeZone: zone).iso }
        }
        XCTAssertEqual(days("2026-01-01", .daily, 3), ["2026-01-01", "2026-01-04", "2026-01-07"])
        XCTAssertEqual(days("2026-01-01", .weekly, 2), ["2026-01-01", "2026-01-15", "2026-01-29"])
        XCTAssertEqual(days("2025-11-30", .monthly, 3), ["2025-11-30", "2026-02-28", "2026-05-30"])
        XCTAssertEqual(days("2024-02-29", .yearly, 2), ["2024-02-29", "2026-02-28", "2028-02-29"])
        XCTAssertEqual(days("2026-01-31", .monthly, 1), ["2026-01-31", "2026-02-28", "2026-03-31"])
        let item = ReminderDefinition(id: UUID(), title: "Care", petName: "Milo", startDay: "2026-01-01", hour: 9, minute: 0, recurrence: .daily, interval: 3)
        let next = ReminderCalendar.next(item, after: CalendarDay(iso: "2026-01-05")!.date(timeZone: zone), timeZone: zone)
        XCTAssertEqual(next.map { CalendarDay($0, timeZone: zone).iso }, "2026-01-07")
    }
    // "validare 1...12 in saveReminder; schimbarea intervalului sterge istoricul de finalizare" (approved plan)
    func testReminderIntervalValidationPersistenceAndCompletionReset() throws {
        var draft = PetDraft(); draft.name = "Milo"
        let pet = try store.savePet(draft, premium: true)
        var reminder = ReminderDraft(); reminder.title = "Care"; reminder.startDay = "2026-01-10"; reminder.recurrence = .monthly
        for invalid in [0, 13] {
            reminder.interval = invalid
            XCTAssertThrowsError(try store.saveReminder(reminder, pet: pet)) { XCTAssertEqual($0 as? CareError, .invalidDate) }
        }
        XCTAssertTrue(store.reminders.isEmpty)
        reminder.interval = 3
        let saved = try store.saveReminder(reminder, pet: pet)
        XCTAssertEqual(ReminderDraft(saved).interval, 3)
        XCTAssertEqual(saved.recurrence.title(interval: saved.interval), "Every 3 months")
        try store.completeReminder(saved, now: CalendarDay(iso: "2026-01-11")!.date())
        XCTAssertEqual(CalendarDay(ReminderCalendar.due(saved.definition)!).iso, "2026-04-10")
        reminder.interval = 2
        try store.saveReminder(reminder, pet: pet, reminder: saved)
        XCTAssertNil(saved.completedThrough)
        // A one-off reminder never keeps an interval.
        reminder.recurrence = .never; reminder.interval = 5
        try store.saveReminder(reminder, pet: pet, reminder: saved)
        XCTAssertEqual(saved.interval, 1)
    }
    // "Daca marchezi accidental un memento nerecurent ca finalizat, apoi il reactivezi fara schimbarea datei, acesta ramane neprogramat."
    func testReenablingCompletedOneOffSchedulesItsOriginalFutureDate() throws {
        var petDraft = PetDraft(); petDraft.name = "Milo"
        let pet = try store.savePet(petDraft, premium: false)
        var draft = ReminderDraft(); draft.title = "Vet"; draft.startDay = "2030-11-10"
        let reminder = try store.saveReminder(draft, pet: pet)
        let now = CalendarDay(iso: "2030-11-01")!.date()
        let originalDate = try XCTUnwrap(ReminderCalendar.due(reminder.definition))
        try store.completeReminder(reminder, now: now)
        XCTAssertFalse(reminder.isEnabled)
        XCTAssertTrue(NotificationPlan.build([reminder.definition], now: now).isEmpty)

        draft = ReminderDraft(reminder); draft.isEnabled = true
        try store.saveReminder(draft, pet: pet, reminder: reminder)
        XCTAssertNil(reminder.completedThrough)
        XCTAssertEqual(ReminderCalendar.due(reminder.definition), originalDate)
        XCTAssertEqual(NotificationPlan.build([reminder.definition], now: now).map(\.date), [originalDate])
    }

    // "Support recurring reminders where appropriate."
    func testPausingAndReenablingRecurringReminderPreservesCompletion() throws {
        var petDraft = PetDraft(); petDraft.name = "Milo"
        let pet = try store.savePet(petDraft, premium: false)
        var draft = ReminderDraft(); draft.title = "Care"; draft.startDay = "2030-01-01"; draft.recurrence = .daily
        let reminder = try store.saveReminder(draft, pet: pet)
        try store.completeReminder(reminder, now: CalendarDay(iso: "2030-01-02")!.date())
        let completed = reminder.completedThrough
        let due = ReminderCalendar.due(reminder.definition)
        draft.isEnabled = false
        try store.saveReminder(draft, pet: pet, reminder: reminder)
        draft.isEnabled = true
        try store.saveReminder(draft, pet: pet, reminder: reminder)
        XCTAssertEqual(reminder.completedThrough, completed)
        XCTAssertEqual(ReminderCalendar.due(reminder.definition), due)
    }

    // "No silent data loss."
    func testFailedOneOffReactivationPreservesCompletedState() throws {
        var petDraft = PetDraft(); petDraft.name = "Milo"
        let pet = try store.savePet(petDraft, premium: false)
        var draft = ReminderDraft(); draft.title = "Vet"; draft.startDay = "2030-11-10"
        let reminder = try store.saveReminder(draft, pet: pet)
        try store.completeReminder(reminder, now: CalendarDay(iso: "2030-11-01")!.date())
        let completed = reminder.completedThrough
        store.saveOperation = { _ in throw CareError.persistence }
        draft.isEnabled = true
        XCTAssertThrowsError(try store.saveReminder(draft, pet: pet, reminder: reminder))
        XCTAssertFalse(reminder.isEnabled)
        XCTAssertEqual(reminder.completedThrough, completed)
    }

    // "pauza mementourilor asociate la mutarea programarii (cu mesaj pentru revizuire)"
    func testAppointmentMovePausesLinkedRemindersAndShowsNotice() throws {
        var petDraft = PetDraft(); petDraft.name = "Milo"
        let pet = try store.savePet(petDraft, premium: false)
        var draft = RecordDraft(); draft.category = .appointment; draft.title = "Vet"
        draft.appointmentAt = CalendarDay(iso: "2026-11-10")!.date()
        let record = try store.saveRecord(draft, pet: pet)
        var reminder = ReminderDraft(); reminder.title = "Vet reminder"; reminder.startDay = "2026-11-10"
        let linked = try store.saveReminder(reminder, pet: pet, record: record)
        draft.notes = "Unrelated edit"
        try store.saveRecord(draft, pet: pet, record: record)
        XCTAssertTrue(linked.isEnabled)
        let model = RecordEditorModel(record: record, category: .appointment)
        model.draft.appointmentAt = CalendarDay(iso: "2026-11-12")!.date()
        XCTAssertTrue(model.save(store: store, pet: pet))
        XCTAssertTrue(model.didPauseReminders)
        XCTAssertFalse(linked.isEnabled)
        XCTAssertTrue(NotificationPlan.build([linked.definition], now: .distantPast).isEmpty)
    }
    // "No silent data loss."
    func testFailedAppointmentMoveDoesNotPauseReminders() throws {
        var petDraft = PetDraft(); petDraft.name = "Milo"
        let pet = try store.savePet(petDraft, premium: false)
        var draft = RecordDraft(); draft.category = .appointment; draft.title = "Vet"
        let oldDate = draft.appointmentAt
        let record = try store.saveRecord(draft, pet: pet)
        var reminder = ReminderDraft(); reminder.title = "Vet reminder"
        let linked = try store.saveReminder(reminder, pet: pet, record: record)
        draft.appointmentAt = oldDate.addingTimeInterval(86400)
        store.saveOperation = { _ in throw CareError.persistence }
        XCTAssertThrowsError(try store.saveRecord(draft, pet: pet, record: record))
        XCTAssertTrue(linked.isEnabled)
        XCTAssertEqual(record.appointmentAt, oldDate)
    }
}

@MainActor final class CalendarTests: XCTestCase {
    // "distinguish date-only values from exact timestamps."
    func testDateOnlyRoundTrip() {
        XCTAssertNotNil(CalendarDay(iso: "2024-02-29"))
        XCTAssertNil(CalendarDay(iso: "2025-02-29"))
        XCTAssertNil(CalendarDay(iso: "2026-04-31"))
        let value = CalendarDay(iso: "2026-11-03")!
        for name in ["Pacific/Kiritimati", "America/Los_Angeles", "Europe/Bucharest"] {
            let zone = TimeZone(identifier: name)!
            XCTAssertEqual(CalendarDay(value.date(timeZone: zone), timeZone: zone), value)
        }
    }
    // "Handle time zones, daylight saving changes, and calendar edge cases."
    func testMonthlyAndYearlyClamping() {
        let zone = TimeZone(secondsFromGMT: 0)!
        var item = ReminderDefinition(id: UUID(), title: "Care", petName: "Milo", startDay: "2024-01-31", hour: 9, minute: 0, recurrence: .monthly)
        XCTAssertEqual(CalendarDay(ReminderCalendar.occurrence(item, index: 1, timeZone: zone)!, timeZone: zone).iso, "2024-02-29")
        XCTAssertEqual(CalendarDay(ReminderCalendar.occurrence(item, index: 2, timeZone: zone)!, timeZone: zone).iso, "2024-03-31")
        item = ReminderDefinition(id: UUID(), title: "Care", petName: "Milo", startDay: "2024-02-29", hour: 9, minute: 0, recurrence: .yearly)
        XCTAssertEqual(CalendarDay(ReminderCalendar.occurrence(item, index: 1, timeZone: zone)!, timeZone: zone).iso, "2025-02-28")
        XCTAssertEqual(CalendarDay(ReminderCalendar.occurrence(item, index: 4, timeZone: zone)!, timeZone: zone).iso, "2028-02-29")
    }
    // "Handle time zones, daylight saving changes, and calendar edge cases."
    func testDailyPreservesWallClockAcrossDST() {
        let zone = TimeZone(identifier: "America/New_York")!
        let item = ReminderDefinition(id: UUID(), title: "Care", petName: "Milo", startDay: "2026-03-07", hour: 9, minute: 0, recurrence: .daily)
        let before = ReminderCalendar.occurrence(item, index: 0, timeZone: zone)!
        let after = ReminderCalendar.occurrence(item, index: 1, timeZone: zone)!
        XCTAssertEqual(after.timeIntervalSince(before), 23 * 3600)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        XCTAssertEqual(calendar.component(.hour, from: after), 9)
    }
    // "Support recurring reminders where appropriate."
    func testNextSkipsDecades() {
        let zone = TimeZone(secondsFromGMT: 0)!
        let item = ReminderDefinition(id: UUID(), title: "Care", petName: "Milo", startDay: "2001-01-01", hour: 9, minute: 0, recurrence: .daily)
        let now = CalendarDay(iso: "2026-11-03")!.date(timeZone: zone)
        XCTAssertEqual(CalendarDay(ReminderCalendar.next(item, after: now, timeZone: zone)!, timeZone: zone).iso, "2026-11-04")
    }
}
