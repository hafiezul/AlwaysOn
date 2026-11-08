import Foundation

/// Tells the user's own input apart from AlwaysOn's. macOS reports a single
/// idle time for all input, synthetic included, so each tick turns it into
/// the time of the latest input and ignores input that matches a post of ours.
struct RealInputTracker: Equatable {
    /// Our posts land within this long of the recorded post time
    /// (the return move or key-up follows 50 ms later)
    static let syntheticMargin: TimeInterval = 1

    private(set) var lastRealInput: Date
    private(set) var lastSyntheticPost: Date?

    init(start: Date) {
        lastRealInput = start
    }

    /// Feed the system idle time measured at `now`, before posting anything
    mutating func observe(idleSeconds: TimeInterval, now: Date) {
        guard idleSeconds.isFinite, idleSeconds >= 0 else { return }
        let latestInput = now.addingTimeInterval(-idleSeconds)
        if let post = lastSyntheticPost,
           abs(latestInput.timeIntervalSince(post)) <= Self.syntheticMargin {
            return
        }
        if latestInput > lastRealInput { lastRealInput = latestInput }
    }

    mutating func recordSyntheticPost(at date: Date) {
        lastSyntheticPost = date
    }

    func awayDuration(now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(lastRealInput))
    }
}

/// Stop a session after the user has been away this long. Protects against
/// a session left running overnight or over a weekend.
enum AwayLimit: Int, CaseIterable, Identifiable {
    case off = 0
    case oneHour = 1
    case twoHours = 2
    case fourHours = 4
    case eightHours = 8

    var id: Int { rawValue }

    var seconds: TimeInterval? {
        self == .off ? nil : TimeInterval(rawValue) * 3600
    }

    var title: String {
        switch self {
        case .off: return "Never"
        case .oneHour: return "1 hour"
        default: return "\(rawValue) hours"
        }
    }

    func isReached(awayFor away: TimeInterval) -> Bool {
        guard let seconds else { return false }
        return away >= seconds
    }
}

/// The Mac's power source, as far as safety stops care
struct BatteryState: Equatable {
    var isOnBattery: Bool
    /// Charge in percent, nil on Macs without a battery
    var percent: Int?

    static let noBattery = BatteryState(isOnBattery: false, percent: nil)

    /// IOKit reports capacity on a 0...max scale, where max is usually 100
    static func percent(current: Int?, maximum: Int?) -> Int? {
        guard let current else { return nil }
        guard let maximum, maximum > 0 else { return current }
        return Int((Double(current) / Double(maximum) * 100).rounded())
    }
}

/// Stop a session when running on battery at or below this charge
enum BatteryStopThreshold: Int, CaseIterable, Identifiable {
    case off = 0
    case ten = 10
    case twenty = 20
    case thirty = 30
    case fifty = 50

    var id: Int { rawValue }

    var title: String {
        self == .off ? "Never" : "At \(rawValue)% on battery"
    }

    func shouldStop(_ state: BatteryState) -> Bool {
        guard self != .off, state.isOnBattery, let percent = state.percent else { return false }
        return percent <= rawValue
    }
}

/// A session AlwaysOn ended on its own, so the menu can say why
struct AutoStopEvent: Equatable {
    enum Reason: Equatable {
        case awayLimit(AwayLimit)
        case lowBattery(percent: Int)
        case timerEnded
        case workHoursEnded
        case permissionRevoked
        case focusEnded

        /// Safety stops also send a notification; the others already have their own
        var isSafetyStop: Bool {
            switch self {
            case .awayLimit, .lowBattery: return true
            case .timerEnded, .workHoursEnded, .permissionRevoked, .focusEnded: return false
            }
        }
    }

    var reason: Reason
    var date: Date

    var title: String {
        switch reason {
        case .awayLimit: return "AlwaysOn Stopped While You Were Away"
        case .lowBattery: return "AlwaysOn Stopped on Low Battery"
        case .timerEnded: return "AlwaysOn Timer Ended"
        case .workHoursEnded: return "Work Hours Ended"
        case .permissionRevoked: return "AlwaysOn Lost Accessibility Permission"
        case .focusEnded: return "Focus Ended"
        }
    }

    var message: String {
        switch reason {
        case .awayLimit(let limit):
            return "No input from you for \(limit.title), so the session ended."
        case .lowBattery(let percent):
            return "The battery reached \(percent)%, so the session ended."
        case .timerEnded:
            return "The session reached its end time."
        case .workHoursEnded:
            return "The work hours schedule ended the session."
        case .permissionRevoked:
            return "Accessibility permission was turned off, so the session stopped."
        case .focusEnded:
            return "The Focus that started the session turned off."
        }
    }

    /// Short form for the menu
    var shortSummary: String {
        let time = date.formatted(date: .omitted, time: .shortened)
        switch reason {
        case .awayLimit(let limit): return "Stopped at \(time) after \(limit.title) away"
        case .lowBattery(let percent): return "Stopped at \(time) at \(percent)% battery"
        case .timerEnded: return "Timer ended at \(time)"
        case .workHoursEnded: return "Work hours ended at \(time)"
        case .permissionRevoked: return "Stopped at \(time): permission turned off"
        case .focusEnded: return "Focus ended at \(time)"
        }
    }

    var symbol: String {
        switch reason {
        case .awayLimit: return "figure.walk"
        case .lowBattery: return "battery.25"
        case .timerEnded: return "timer"
        case .workHoursEnded: return "calendar.badge.clock"
        case .permissionRevoked: return "lock.slash"
        case .focusEnded: return "moon.circle"
        }
    }
}
