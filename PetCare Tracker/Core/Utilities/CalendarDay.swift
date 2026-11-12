import Foundation

/// A Gregorian date-only value; it never encodes a midnight UTC timestamp.
nonisolated struct CalendarDay: Equatable, Comparable, Codable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(_ date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year!; month = components.month!; day = components.day!
    }

    init?(iso: String) {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...9999).contains(y), (1...12).contains(m), (1...31).contains(d) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: y, month: m, day: d)),
              calendar.component(.day, from: date) == d else { return nil }
        year = y; month = m; day = d
        guard self.iso == iso else { return nil }
    }

    var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    func date(timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    func instant(hour: Int, minute: Int, timeZone: TimeZone) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let midnight = calendar.startOfDay(for: date(timeZone: timeZone))
        // Missing DST times move forward; repeated times use the first occurrence.
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: midnight,
                             matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.iso < rhs.iso }
}

nonisolated struct ReminderDefinition: Equatable, Sendable {
    let id: UUID
    let title: String
    let petName: String
    let startDay: String
    let hour: Int
    let minute: Int
    let recurrence: RepeatRule
    var isEnabled: Bool = true
    var completedThrough: Date?
    var interval: Int = 1
}

nonisolated enum ReminderCalendar {
    /// Monthly/yearly repetitions retain the original day, clamping to the month's last day.
    static func occurrence(_ item: ReminderDefinition, index: Int, timeZone: TimeZone) -> Date? {
        guard index >= 0, let anchor = CalendarDay(iso: item.startDay) else { return nil }
        let index = index * max(1, item.interval)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let day: CalendarDay
        switch item.recurrence {
        case .never:
            guard index == 0 else { return nil }; day = anchor
        case .daily, .weekly:
            guard let date = calendar.date(byAdding: .day, value: index * (item.recurrence == .weekly ? 7 : 1), to: anchor.date(timeZone: timeZone)) else { return nil }
            day = CalendarDay(date, timeZone: timeZone)
        case .monthly, .yearly:
            let component: Calendar.Component = item.recurrence == .monthly ? .month : .year
            let first = calendar.date(from: DateComponents(year: anchor.year, month: anchor.month, day: 1, hour: 12))!
            guard let shifted = calendar.date(byAdding: component, value: index, to: first),
                  let days = calendar.range(of: .day, in: .month, for: shifted) else { return nil }
            let c = calendar.dateComponents([.year, .month], from: shifted)
            guard let value = CalendarDay(iso: String(format: "%04d-%02d-%02d", c.year!, c.month!, min(anchor.day, days.count))) else { return nil }
            day = value
        }
        return day.instant(hour: item.hour, minute: item.minute, timeZone: timeZone)
    }

    static func next(_ item: ReminderDefinition, after date: Date, timeZone: TimeZone = .current) -> Date? {
        guard item.isEnabled, let start = occurrence(item, index: 0, timeZone: timeZone) else { return nil }
        let threshold = max(date, item.completedThrough ?? .distantPast)
        if start > threshold { return start }
        guard item.recurrence != .never else { return nil }
        // Binary search avoids iterating years of daily reminders on every activation.
        var lower = 0, upper = 1
        while let value = occurrence(item, index: upper, timeZone: timeZone), value <= threshold {
            lower = upper; upper *= 2
            guard upper < 4_000_000 else { return nil }
        }
        while lower + 1 < upper {
            let middle = (lower + upper) / 2
            guard let value = occurrence(item, index: middle, timeZone: timeZone) else { return nil }
            if value <= threshold { lower = middle } else { upper = middle }
        }
        return occurrence(item, index: upper, timeZone: timeZone)
    }

    static func due(_ item: ReminderDefinition, timeZone: TimeZone = .current) -> Date? {
        guard item.isEnabled else { return nil }
        if let completed = item.completedThrough { return next(item, after: completed, timeZone: timeZone) }
        return occurrence(item, index: 0, timeZone: timeZone)
    }
}
