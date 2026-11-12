import Foundation

/// A calendar event reduced to what day-off suggestions need. Titles are
/// shown to the user once and never saved.
struct CalendarBlock: Equatable {
    enum Availability: Equatable { case outOfOffice, busy, tentative, free, unknown }
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var availability: Availability
}

/// A workday the user might want to add to Days Off
struct DayOffSuggestion: Identifiable, Equatable {
    /// "yyyy-MM-dd", the same key WorkSchedule.skippedDays uses
    var id: String
    /// Start of that local day
    var date: Date
    /// Title of the event that covers the day
    var reason: String
    /// Marked out of office, not just an all-day event
    var isOutOfOffice: Bool
}

/// Finds workdays whose whole working time is covered by an out-of-office
/// event, or by an all-day event that isn't marked free. Only days that
/// have work hours and aren't already days off are suggested.
enum CalendarDaysOff {
    static let lookAheadDays = 60

    static func suggestions(from blocks: [CalendarBlock], schedule: WorkSchedule, from now: Date,
                            days: Int = lookAheadDays, calendar: Calendar = .current) -> [DayOffSuggestion] {
        let candidates = blocks.filter { $0.availability == .outOfOffice || ($0.isAllDay && $0.availability != .free) }
        guard !candidates.isEmpty else { return [] }
        var result: [DayOffSuggestion] = []
        let firstDay = calendar.startOfDay(for: now)
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { continue }
            let windows = schedule.windows(on: day, calendar: calendar)
            guard let first = windows.first, let last = windows.last,
                  let workStart = calendar.date(bySettingHour: first.startMinutes / 60, minute: first.startMinutes % 60, second: 0, of: day),
                  let workEnd = calendar.date(bySettingHour: last.endMinutes / 60, minute: last.endMinutes % 60, second: 0, of: day) else { continue }
            let covering = candidates.filter { $0.start <= workStart && $0.end >= workEnd }
            guard let pick = covering.first(where: { $0.availability == .outOfOffice }) ?? covering.first else { continue }
            let title = pick.title.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(DayOffSuggestion(id: WorkSchedule.dayKey(for: day, calendar: calendar), date: day,
                                           reason: title.isEmpty ? "Untitled event" : title,
                                           isOutOfOffice: pick.availability == .outOfOffice))
        }
        return result
    }
}
