import Foundation
import UserNotifications
import Observation

struct ScheduledCare: Equatable {
    let reminderID: UUID
    let date: Date
    let title: String
    var identifier: String { "petcare." + reminderID.uuidString + "." + String(Int(date.timeIntervalSince1970)) }
}

enum NotificationPlan {
    static let capacity = 64
    static func build(_ definitions: [ReminderDefinition], now: Date, timeZone: TimeZone = .current, capacity: Int = capacity) -> [ScheduledCare] {
        guard capacity > 0 else { return [] }
        // One candidate per definition keeps work proportional to pets/reminders, not years elapsed.
        var seen = Set<UUID>()
        var candidates = definitions.filter { $0.isEnabled && seen.insert($0.id).inserted }.compactMap { item -> (ReminderDefinition, Date)? in
            ReminderCalendar.next(item, after: now, timeZone: timeZone).map { (item, $0) }
        }
        var result: [ScheduledCare] = []
        while result.count < capacity, !candidates.isEmpty {
            candidates.sort { $0.1 == $1.1 ? $0.0.id.uuidString < $1.0.id.uuidString : $0.1 < $1.1 }
            let (item, date) = candidates.removeFirst()
            result.append(ScheduledCare(reminderID: item.id, date: date, title: item.title))
            if let next = ReminderCalendar.next(item, after: date, timeZone: timeZone) { candidates.append((item, next)) }
        }
        return result
    }
}

@MainActor protocol NotificationClient {
    func authorization() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func pendingIdentifiers() async -> [String]
    func remove(_ identifiers: [String])
    func removeDelivered(except reminderIDs: Set<UUID>) async
    func add(_ item: ScheduledCare, timeZone: TimeZone) async throws
}

@MainActor final class SystemNotificationClient: NotificationClient {
    private let center = UNUserNotificationCenter.current()
    func authorization() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
    func pendingIdentifiers() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }
    func remove(_ identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    func removeDelivered(except reminderIDs: Set<UUID>) async {
        let delivered = await center.deliveredNotifications()
        let obsolete = delivered.filter { notification in
            let parts = notification.request.identifier.split(separator: ".")
            guard parts.count == 3, parts[0] == "petcare", let id = UUID(uuidString: String(parts[1])) else { return false }
            return !reminderIDs.contains(id)
        }.map { $0.request.identifier }
        center.removeDeliveredNotifications(withIdentifiers: obsolete)
    }
    func add(_ item: ScheduledCare, timeZone: TimeZone) async throws {
        let content = UNMutableNotificationContent()
        // No health notes, microchip or owner details on the lock screen.
        content.title = L10n.text("Pet care reminder")
        content.body = L10n.text("Open Pet Care Tracker to review your care activity.")
        content.sound = .default
        content.userInfo = ["reminderID": item.reminderID.uuidString]
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.date)
        parts.timeZone = timeZone; parts.calendar = calendar
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
    }
}

@MainActor @Observable final class NotificationScheduler {
    private let client: any NotificationClient
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var scheduledCount = 0
    private(set) var scheduledThrough: Date?
    private(set) var error: String?
    private var latest: [ReminderDefinition] = []
    private var latestNow = Date()
    private var latestTimeZone = TimeZone.current
    private var dirty = false
    private var running = false
    init(client: any NotificationClient) { self.client = client }

    func requestPermission() async {
        do { _ = try await client.requestAuthorization() }
        catch { self.error = L10n.text("Notification permission could not be requested. Please try again.") }
        authorization = await client.authorization()
    }

    func reconcile(_ definitions: [ReminderDefinition], now: Date = Date(), timeZone: TimeZone = .current) async {
        latest = definitions; latestNow = now; latestTimeZone = timeZone; dirty = true
        guard !running else { return }
        running = true
        defer { running = false }
        while dirty {
            dirty = false
            let snapshot = latest
            let scheduleNow = latestNow
            let scheduleTimeZone = latestTimeZone
            authorization = await client.authorization()
            let existing = await client.pendingIdentifiers()
            let own = existing.filter { $0.hasPrefix("petcare.") }
            let allowed = authorization == .authorized || authorization == .provisional || authorization == .ephemeral
            let available = max(0, NotificationPlan.capacity - existing.count + own.count)
            let plan = allowed ? NotificationPlan.build(snapshot, now: scheduleNow, timeZone: scheduleTimeZone, capacity: available) : []
            let desired = Set(plan.map(\.identifier))
            client.remove(own.filter { !desired.contains($0) })
            await client.removeDelivered(except: Set(snapshot.filter(\.isEnabled).map(\.id)))
            scheduledCount = 0; scheduledThrough = nil; error = nil
            for item in plan {
                do { try await client.add(item, timeZone: scheduleTimeZone); scheduledCount += 1; scheduledThrough = item.date }
                catch { self.error = L10n.text("Some notifications could not be scheduled. Reopen the app to try again."); break }
            }
        }
    }
}
