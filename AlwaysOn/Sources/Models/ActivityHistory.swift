import Foundation

/// How a session was started, as recorded in activity history
enum SessionKind: String, Codable, CaseIterable, Identifiable {
    case manual, schedule, timer, until, command, focus

    var id: String { rawValue }

    init(_ source: SessionSource?) {
        switch source {
        case .none, .manual: self = .manual
        case .workSchedule: self = .schedule
        case .quickTimer: self = .timer
        case .until: self = .until
        case .command: self = .command
        case .focus: self = .focus
        }
    }

    var title: String {
        switch self {
        case .manual: return "Manual"
        case .schedule: return "Work hours"
        case .timer: return "Timer"
        case .until: return "Until"
        case .command: return "Command"
        case .focus: return "Focus"
        }
    }
}

/// A stretch of time AlwaysOn kept the user online
struct ActivitySegment: Codable, Equatable {
    var start: Date
    var end: Date
    var kind: SessionKind

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    /// Seconds of this segment inside `interval`
    func overlap(with interval: DateInterval) -> TimeInterval {
        let lower = max(start, interval.start)
        let upper = min(end, interval.end)
        return max(0, upper.timeIntervalSince(lower))
    }
}

/// Online time per day, split by how sessions started
struct DailyActivity: Equatable, Identifiable {
    var day: Date
    var byKind: [SessionKind: TimeInterval]

    var id: Date { day }
    var total: TimeInterval { byKind.values.reduce(0, +) }
}

/// Recorded online time. "Online" means a session was active and the Mac was
/// awake, unlocked (when pausing on lock), and on this user's session.
/// Value type so the rules are testable without files or clocks.
struct ActivityLedger: Codable, Equatable {
    /// The segment still running, with the last time it was known to be running
    struct OpenSegment: Codable, Equatable {
        var start: Date
        var kind: SessionKind
        var lastSeen: Date
    }

    static let retentionDays = 30
    /// Segments shorter than this are bookkeeping noise (state flips within one update)
    static let minimumSegment: TimeInterval = 1

    private(set) var segments: [ActivitySegment] = []
    private(set) var open: OpenSegment?

    var isRecording: Bool { open != nil }

    /// Moves the ledger to the given state: starts, switches, or ends the open segment
    /// - Returns: Whether anything changed that should be saved
    @discardableResult
    mutating func update(isOnline: Bool, kind: SessionKind, now: Date) -> Bool {
        if let open, isOnline, open.kind == kind { return false }
        let closed = close(at: now)
        if isOnline {
            open = OpenSegment(start: now, kind: kind, lastSeen: now)
            return true
        }
        return closed
    }

    /// Records that the open segment is still running, so a crash loses at most
    /// the time since the last checkpoint
    mutating func checkpoint(at now: Date) {
        guard var current = open else { return }
        current.lastSeen = max(current.lastSeen, now)
        open = current
    }

    /// Closes the open segment at `date`. Returns whether a segment was kept.
    @discardableResult
    mutating func close(at date: Date) -> Bool {
        guard let current = open else { return false }
        open = nil
        let end = max(date, current.start)
        guard end.timeIntervalSince(current.start) >= Self.minimumSegment else { return false }
        segments.append(ActivitySegment(start: current.start, end: end, kind: current.kind))
        return true
    }

    /// After a relaunch the open segment's true end is unknown; keep what is
    /// known by closing it at the last time it was seen running
    mutating func recoverAfterRelaunch() {
        if let open { close(at: open.lastSeen) }
    }

    /// Drops segments that ended before the retention window
    mutating func prune(now: Date, calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays,
                                         to: calendar.startOfDay(for: now)) else { return }
        segments.removeAll { $0.end < cutoff }
    }

    mutating func clear() {
        segments = []
        open = nil
    }

    /// All segments, with the open one running until `now`
    func segmentsIncludingOpen(now: Date) -> [ActivitySegment] {
        guard let open else { return segments }
        return segments + [ActivitySegment(start: open.start, end: max(now, open.start), kind: open.kind)]
    }

    /// Online seconds inside `interval`, counting the open segment up to `now`
    func onlineTime(in interval: DateInterval, now: Date) -> TimeInterval {
        segmentsIncludingOpen(now: now).reduce(0) { $0 + $1.overlap(with: interval) }
    }

    /// Online seconds on the calendar day containing `now`
    func today(now: Date, calendar: Calendar = .current) -> TimeInterval {
        guard let interval = calendar.dateInterval(of: .day, for: now) else { return 0 }
        return onlineTime(in: interval, now: now)
    }

    /// One entry per calendar day for the last `days` days ending today, oldest first.
    /// Segments that cross midnight are split between the days they cover.
    func daily(days: Int, now: Date, calendar: Calendar = .current) -> [DailyActivity] {
        let all = segmentsIncludingOpen(now: now)
        let today = calendar.startOfDay(for: now)
        return (0..<max(days, 0)).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let interval = calendar.dateInterval(of: .day, for: day) else { return nil }
            var byKind: [SessionKind: TimeInterval] = [:]
            for segment in all {
                let seconds = segment.overlap(with: interval)
                if seconds > 0 { byKind[segment.kind, default: 0] += seconds }
            }
            return DailyActivity(day: day, byKind: byKind)
        }
    }
}

/// Formats online durations as "3h 12m", "45m", or "<1m"
enum ActivityDurationFormat {
    static func long(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        if totalMinutes < 1 { return seconds > 0 ? "<1m" : "0m" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}
