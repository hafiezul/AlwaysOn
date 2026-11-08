import Foundation

/// Represents a work schedule for automatic enable/disable
struct WorkSchedule: Codable, Equatable {
    
    // MARK: - Properties
    
    /// Whether the schedule is enabled
    var isEnabled: Bool
    
    /// Days of the week when the schedule is active (1 = Sunday, 7 = Saturday)
    var activeDays: Set<Int>
    
    /// Start time as minutes from midnight (e.g., 9:00 AM = 540)
    var startTimeMinutes: Int
    
    /// End time as minutes from midnight (e.g., 5:00 PM = 1020)
    var endTimeMinutes: Int

    /// Hours for particular weekdays that differ from the start and end above
    var customHours: [DayHours] = []

    /// A daily break, such as lunch, when work hours pause
    var breakTime: MinuteRange?

    /// Local dates ("yyyy-MM-dd") with no work hours: holidays, days off, Skip Today
    var skippedDays: Set<String> = []
    
    // MARK: - Computed Properties
    
    /// Start time as a Date (today with the scheduled time)
    var startTime: Date {
        Calendar.current.date(bySettingHour: startTimeMinutes / 60, minute: startTimeMinutes % 60, second: 0, of: Date()) ?? Date()
    }
    
    /// End time as a Date (today with the scheduled time)
    var endTime: Date {
        Calendar.current.date(bySettingHour: endTimeMinutes / 60, minute: endTimeMinutes % 60, second: 0, of: Date()) ?? Date()
    }
    
    /// Formatted start time string
    var startTimeString: String {
        return Self.timeFormatter.string(from: startTime)
    }
    
    /// Formatted end time string
    var endTimeString: String {
        return Self.timeFormatter.string(from: endTime)
    }
    
    /// Whether the current time falls within the scheduled work hours
    var isCurrentlyWithinSchedule: Bool {
        isWithinSchedule(on: Date())
    }
    
    /// Whether the given time falls within the scheduled work hours
    func isWithinSchedule(on date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        let currentMinutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return windows(on: date, calendar: calendar).contains { $0.contains(currentMinutes) }
    }

    // MARK: - Days, Hours, and Breaks

    /// Start and end minutes for a weekday: its custom hours, or the default
    func hours(forWeekday weekday: Int) -> MinuteRange {
        if let custom = customHours.first(where: { $0.weekday == weekday }) { return custom.range }
        return MinuteRange(startMinutes: startTimeMinutes, endMinutes: endTimeMinutes)
    }

    /// Whether a weekday has hours of its own
    func hasCustomHours(forWeekday weekday: Int) -> Bool {
        customHours.contains { $0.weekday == weekday }
    }

    /// Gives a weekday its own hours; nil goes back to the default hours
    mutating func setHours(_ range: MinuteRange?, forWeekday weekday: Int) {
        customHours.removeAll { $0.weekday == weekday }
        guard let range else { return }
        customHours.append(DayHours(weekday: weekday, range: range.validated))
        customHours.sort { $0.weekday < $1.weekday }
    }

    /// The work periods on the day containing `date`, as minutes from
    /// midnight, earliest first. Empty on inactive or skipped days. A break
    /// splits the day's hours in two.
    func windows(on date: Date, calendar: Calendar = .current) -> [MinuteRange] {
        let weekday = calendar.component(.weekday, from: date)
        guard activeDays.contains(weekday), !isSkipped(date, calendar: calendar) else { return [] }
        let dayHours = hours(forWeekday: weekday)
        guard let breakTime, breakTime.startMinutes < dayHours.endMinutes, breakTime.endMinutes > dayHours.startMinutes else {
            return [dayHours]
        }
        return [MinuteRange(startMinutes: dayHours.startMinutes, endMinutes: breakTime.startMinutes),
                MinuteRange(startMinutes: breakTime.endMinutes, endMinutes: dayHours.endMinutes)]
            .filter { $0.startMinutes < $0.endMinutes }
    }

    /// When work hours finish on the day containing `date` (after any break),
    /// nil when that day has none
    func workdayEnd(on date: Date, calendar: Calendar = .current) -> Date? {
        guard let last = windows(on: date, calendar: calendar).last else { return nil }
        return calendar.date(bySettingHour: last.endMinutes / 60, minute: last.endMinutes % 60, second: 0, of: date)
    }

    // MARK: - Skipped Days

    /// The local calendar day of `date` as "yyyy-MM-dd"
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func isSkipped(_ date: Date, calendar: Calendar = .current) -> Bool {
        skippedDays.contains(Self.dayKey(for: date, calendar: calendar))
    }

    mutating func setSkipped(_ skipped: Bool, on date: Date, calendar: Calendar = .current) {
        let key = Self.dayKey(for: date, calendar: calendar)
        if skipped { skippedDays.insert(key) } else { skippedDays.remove(key) }
    }

    /// Drops skipped days before the day containing `date`, so the list
    /// doesn't grow forever. Keys sort chronologically as strings.
    mutating func pruneSkippedDays(before date: Date, calendar: Calendar = .current) {
        let today = Self.dayKey(for: date, calendar: calendar)
        skippedDays = skippedDays.filter { $0 >= today }
    }

    /// Whether the day containing `date` would have work hours if it weren't skipped
    func isWorkday(_ date: Date, calendar: Calendar = .current) -> Bool {
        activeDays.contains(calendar.component(.weekday, from: date))
    }
    
    /// Human-readable description of active days
    var activeDaysDescription: String {
        if activeDays.isEmpty {
            return "No days selected"
        }
        
        // Check for common patterns
        if activeDays == Set([2, 3, 4, 5, 6]) {
            return "Weekdays"
        } else if activeDays == Set([1, 7]) {
            return "Weekends"
        } else if activeDays == Set(1...7) {
            return "Every day"
        }
        
        let sortedDays = activeDays.sorted()
        let dayNames = sortedDays.map { dayName(for: $0) }
        return dayNames.joined(separator: ", ")
    }
    
    // MARK: - Initialization
    
    init(isEnabled: Bool = false, activeDays: Set<Int> = [2, 3, 4, 5, 6], startTimeMinutes: Int = 540, endTimeMinutes: Int = 1020) {
        self.isEnabled = isEnabled
        self.activeDays = activeDays
        // Ensure valid time range (start < end with minimum 1 minute gap)
        let validatedStart = max(0, min(startTimeMinutes, 1438)) // Max 23:58 to allow 1 min for end
        let validatedEnd = max(validatedStart + 1, min(endTimeMinutes, 1439)) // Min 1 min after start, max 23:59
        self.startTimeMinutes = validatedStart
        self.endTimeMinutes = validatedEnd
    }
    
    // MARK: - Validation
    
    /// Whether the schedule has valid time settings (start < end)
    var isValidTimeRange: Bool {
        startTimeMinutes < endTimeMinutes
    }
    
    /// Minimum gap between start and end times in minutes
    static let minimumTimeGap = 1
    
    // MARK: - Static Defaults
    
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
    
    /// Default work schedule: Monday-Friday, 9 AM - 5 PM
    static let `default` = WorkSchedule(
        isEnabled: false,
        activeDays: [2, 3, 4, 5, 6], // Mon-Fri
        startTimeMinutes: 9 * 60,     // 9:00 AM
        endTimeMinutes: 17 * 60       // 5:00 PM
    )
    
    // MARK: - Helper Methods
    
    /// Get the short name for a weekday
    private func dayName(for weekday: Int) -> String {
        let symbols = Self.shortWeekdaySymbols
        return symbols[(weekday - 1) % 7]
    }
    
    /// Check if a specific day is active
    func isDayActive(_ weekday: Int) -> Bool {
        activeDays.contains(weekday)
    }
    
    /// Toggle a specific day
    mutating func toggleDay(_ weekday: Int) {
        if activeDays.contains(weekday) {
            activeDays.remove(weekday)
        } else {
            activeDays.insert(weekday)
        }
    }
    
    private static let shortWeekdaySymbols: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.shortWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    }()
    
    /// The next moment after `date` when the schedule starts or ends, nil when it never changes.
    /// Built from calendar dates rather than fixed second offsets so it stays correct across
    /// daylight saving changes.
    func nextTransition(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isEnabled, !activeDays.isEmpty else { return nil }
        let today = calendar.startOfDay(for: date)
        // Look far enough ahead to clear a long run of skipped days
        for dayOffset in 0...Self.transitionSearchDays {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            for window in windows(on: day, calendar: calendar) {
                for minutes in [window.startMinutes, window.endMinutes] {
                    if let moment = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                       moment > date {
                        return moment
                    }
                }
            }
        }
        return nil
    }

    /// How many days ahead nextTransition looks
    static let transitionSearchDays = 400

    /// One line for the menu: when work hours end, or when they next start
    func menuHint(now: Date, calendar: Calendar = .current) -> String? {
        guard let next = nextTransition(after: now, calendar: calendar) else { return nil }
        let time = next.formatted(date: .omitted, time: .shortened)
        if isWithinSchedule(on: now, calendar: calendar) {
            let hasBreakAhead = windows(on: now, calendar: calendar).count > 1 && next != workdayEnd(on: now, calendar: calendar)
            return hasBreakAhead ? "Work hours until \(time), then a break" : "Work hours until \(time)"
        }
        let day: String
        if calendar.isDate(next, inSameDayAs: now) {
            day = "today"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                  calendar.isDate(next, inSameDayAs: tomorrow) {
            day = "tomorrow"
        } else {
            day = next.formatted(.dateTime.weekday(.wide))
        }
        let skippedToday = isSkipped(now, calendar: calendar) && isWorkday(now, calendar: calendar)
        return (skippedToday ? "Skipping today · " : "") + "Work hours start \(day) at \(time)"
    }

    /// Time until work hours next start, nil while within them or when they never start
    func timeUntilNextStart(now: Date = Date()) -> TimeInterval? {
        guard isEnabled, !isWithinSchedule(on: now), let next = nextTransition(after: now) else { return nil }
        return next.timeIntervalSince(now)
    }

    /// Time until the current work period ends (a break or the end of the day)
    func timeUntilEnd(now: Date = Date()) -> TimeInterval? {
        guard isWithinSchedule(on: now), let next = nextTransition(after: now) else { return nil }
        return next.timeIntervalSince(now)
    }
}

// MARK: - Hours Types

/// A span of the day in minutes from midnight, start inclusive, end exclusive
struct MinuteRange: Codable, Equatable {
    var startMinutes: Int
    var endMinutes: Int

    func contains(_ minutes: Int) -> Bool {
        minutes >= startMinutes && minutes < endMinutes
    }

    /// Clamped into the day with the end at least a minute after the start
    var validated: MinuteRange {
        let start = max(0, min(startMinutes, 1438))
        return MinuteRange(startMinutes: start, endMinutes: max(start + 1, min(endMinutes, 1439)))
    }

    /// "12:00 PM – 1:00 PM"
    var formatted: String {
        "\(Self.format(startMinutes)) – \(Self.format(endMinutes))"
    }

    static func format(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Hours for one weekday that differ from the schedule's default
struct DayHours: Codable, Equatable, Identifiable {
    /// 1 = Sunday ... 7 = Saturday
    var weekday: Int
    var range: MinuteRange

    var id: Int { weekday }
}

extension WorkSchedule {
    private enum CodingKeys: String, CodingKey {
        case isEnabled, activeDays, startTimeMinutes, endTimeMinutes, customHours, breakTime, skippedDays
    }

    /// Schedules saved before custom hours, breaks, and skipped days have none
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        activeDays = try container.decode(Set<Int>.self, forKey: .activeDays)
        startTimeMinutes = try container.decode(Int.self, forKey: .startTimeMinutes)
        endTimeMinutes = try container.decode(Int.self, forKey: .endTimeMinutes)
        customHours = try container.decodeIfPresent([DayHours].self, forKey: .customHours) ?? []
        breakTime = try container.decodeIfPresent(MinuteRange.self, forKey: .breakTime)
        skippedDays = try container.decodeIfPresent(Set<String>.self, forKey: .skippedDays) ?? []
    }
}

// MARK: - Day of Week Helper

enum DayOfWeek: Int, CaseIterable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    
    var id: Int { rawValue }
    
    var shortName: String {
        let symbols = Self.shortSymbols
        return symbols[(rawValue - 1) % 7]
    }
    
    var name: String {
        let symbols = Self.fullSymbols
        return symbols[(rawValue - 1) % 7]
    }
    
    private static let shortSymbols: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.shortWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    }()
    
    private static let fullSymbols: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.weekdaySymbols ?? ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    }()
    
    /// Returns weekdays in the order starting from Monday (more common for work schedules)
    static var workWeekOrder: [DayOfWeek] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }
}
