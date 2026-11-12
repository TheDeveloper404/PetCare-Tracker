import Foundation
import SwiftData
import Observation

#if DEBUG
/// UI tests only: premium without StoreKit, so multi-pet flows can run in the simulator.
@MainActor private final class UITestingPremiumProvider: PurchaseProvider {
    let changes = AsyncStream<Void> { $0.finish() }
    func product() async throws -> PremiumProduct? { nil }
    func purchase() async throws -> PurchaseOutcome { .purchased }
    func restore() async throws {}
    func hasEntitlement() async throws -> Bool { true }
}

/// App Store screenshots only: representative sample data in the separate UI-testing store.
@MainActor private func seedDemoData(_ store: CareStore) throws {
    let romanian = UserDefaults.standard.string(forKey: "appLanguage") == "ro"
    func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: Date())! }
    var luna = PetDraft(); luna.name = "Luna"; luna.breed = "Golden Retriever"; luna.birthDay = "2022-05-14"
    luna.sex = "Female"; luna.microchip = "642090001234567"
    luna.vetName = "Happy Paws Clinic"; luna.vetPhone = "+40 21 555 0142"
    let dog = try store.savePet(luna, premium: true)
    var milo = PetDraft(); milo.name = "Milo"; milo.species = "Cat"; milo.breed = "British Shorthair"; milo.sex = "Male"
    let cat = try store.savePet(milo, premium: true)
    for (category, offset, english, local) in [
        (RecordCategory.veterinary, -75, "Annual check-up", "Control anual"),
        (.vaccination, -40, "Rabies vaccination", "Vaccin antirabic"),
        (.parasite, -12, "Deworming", "Deparazitare internă"),
        (.appointment, 6, "Dental cleaning", "Detartraj")] {
        var record = RecordDraft(); record.category = category; record.title = romanian ? local : english
        record.day = CalendarDay(day(offset)).iso
        record.appointmentAt = Calendar.current.date(bySettingHour: 10, minute: 30, second: 0, of: day(offset))!
        try store.saveRecord(record, pet: dog)
    }
    var vaccine = RecordDraft(); vaccine.title = romanian ? "Vaccin trivalent" : "Core vaccination"; vaccine.day = CalendarDay(day(-20)).iso
    try store.saveRecord(vaccine, pet: cat)
    for (offset, kilograms) in [(-150, 27.4), (-120, 27.9), (-90, 28.3), (-60, 28.1), (-30, 28.8), (-3, 29.2)] {
        try store.saveWeight(pet: dog, day: CalendarDay(day(offset)).iso, kilograms: kilograms, notes: "")
    }
    for (pet, offset, hour, rule, interval, english, local) in [
        (dog, 4, 9, RepeatRule.monthly, 3, "Flea and tick treatment", "Tratament antiparazitar"),
        (cat, 1, 19, .daily, 1, "Evening medication", "Medicament de seară"),
        (cat, 20, 10, .yearly, 1, "Vaccination booster", "Rapel vaccin")] {
        var reminder = ReminderDraft(); reminder.title = romanian ? local : english
        reminder.startDay = CalendarDay(day(offset)).iso; reminder.hour = hour; reminder.recurrence = rule; reminder.interval = interval
        try store.saveReminder(reminder, pet: pet)
    }
}
#endif

@MainActor @Observable final class AppServices {
    let store: CareStore
    let notifications: NotificationScheduler
    let premium: PremiumStore
    init(store: CareStore, notifications: NotificationScheduler, premium: PremiumStore) {
        self.store = store; self.notifications = notifications; self.premium = premium
    }
    static func live() throws -> AppServices {
        let files = FileManager.default
        var directory = try files.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("PetCareTracker", isDirectory: true)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            directory = files.temporaryDirectory.appendingPathComponent("PetCareTrackerUITests", isDirectory: true)
            if ProcessInfo.processInfo.arguments.contains("--reset-ui-testing"), files.fileExists(atPath: directory.path) {
                try files.removeItem(at: directory)
            }
        }
        #endif
        // Exports interrupted before the share sheet closed are removed on the next launch.
        try? files.removeItem(at: files.temporaryDirectory.appendingPathComponent("PetCareExports", isDirectory: true))
        try files.createDirectory(at: directory, withIntermediateDirectories: true,
                                  attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let photos = try PhotoStore(directory: directory.appendingPathComponent("Photos", isDirectory: true))
        let store = try CareStore(container: Persistence.container(url: directory.appendingPathComponent("Care.store")), photos: photos)
        var id = Bundle.main.object(forInfoDictionaryKey: "PremiumProductID") as? String ?? ""
        #if DEBUG
        // As the unit-test host the app must not contact StoreKit: an early production lookup
        // prevents SKTestSession from publishing the local test product.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { id = "" }
        #endif
        var provider: any PurchaseProvider = StoreKitProvider(productID: id)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--ui-testing-demo"), store.pets.isEmpty {
            try seedDemoData(store)
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--ui-testing-premium") {
            provider = UITestingPremiumProvider()
        }
        #endif
        return AppServices(store: store, notifications: NotificationScheduler(client: SystemNotificationClient()),
                           premium: PremiumStore(provider: provider))
    }
    func reconcile() async {
        await notifications.reconcile(store.reminders.map(\.definition))
    }
    func activate() async {
        store.refresh()
        await premium.refresh()
        await reconcile()
    }
}
