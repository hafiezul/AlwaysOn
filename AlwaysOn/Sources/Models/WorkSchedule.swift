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
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }
    
    /// Formatted end time string
    var endTimeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: endTime)
    }
    
    /// Whether the current time falls within the scheduled work hours
    var isCurrentlyWithinSchedule: Bool {
        guard isEnabled else { return false }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Check if today is an active day
        let weekday = calendar.component(.weekday, from: now)
        guard activeDays.contains(weekday) else { return false }
        
        // Check if current time is within the schedule
        let currentMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        return currentMinutes >= startTimeMinutes && currentMinutes < endTimeMinutes
    }
    
    /// Human-readable description of active days
    var activeDaysDescription: String {
        if activeDays.isEmpty {
            return "No days selected"
        }
        
        let sortedDays = activeDays.sorted()
        let dayNames = sortedDays.map { dayName(for: $0) }
        
        // Check for common patterns
        if activeDays == Set([2, 3, 4, 5, 6]) {
            return "Weekdays"
        } else if activeDays == Set([1, 7]) {
            return "Weekends"
        } else if activeDays == Set(1...7) {
            return "Every day"
        }
        
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
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let symbols = formatter.shortWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
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
    
    /// Calculate time until next schedule start (nil if currently within schedule or schedule disabled)
    func timeUntilNextStart() -> TimeInterval? {
        guard isEnabled, !isCurrentlyWithinSchedule else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        let currentWeekday = calendar.component(.weekday, from: now)
        let currentMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        
        // Try to find the next active day
        for dayOffset in 0..<8 {
            let targetWeekday = ((currentWeekday - 1 + dayOffset) % 7) + 1
            
            guard activeDays.contains(targetWeekday) else { continue }
            
            // If it's today and we haven't passed the start time, return time until start
            if dayOffset == 0 && currentMinutes < startTimeMinutes {
                return TimeInterval((startTimeMinutes - currentMinutes) * 60)
            }
            
            // For future days, calculate full time
            if dayOffset > 0 {
                let daysUntil = TimeInterval(dayOffset * 24 * 60 * 60)
                let minutesUntilStart = TimeInterval(startTimeMinutes * 60)
                let minutesSinceMidnight = TimeInterval(currentMinutes * 60)
                return daysUntil + minutesUntilStart - minutesSinceMidnight
            }
        }
        
        return nil
    }
    
    /// Calculate time until schedule end (nil if not currently within schedule)
    func timeUntilEnd() -> TimeInterval? {
        guard isCurrentlyWithinSchedule else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        let currentMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        
        return TimeInterval((endTimeMinutes - currentMinutes) * 60)
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
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let symbols = formatter.shortWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return symbols[(rawValue - 1) % 7]
    }
    
    var name: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let symbols = formatter.weekdaySymbols ?? ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return symbols[(rawValue - 1) % 7]
    }
    
    /// Returns weekdays in the order starting from Monday (more common for work schedules)
    static var workWeekOrder: [DayOfWeek] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }
}
