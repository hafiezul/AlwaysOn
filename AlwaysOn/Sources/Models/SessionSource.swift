import Foundation

/// Codable case names retain the persisted format of existing sessions.
enum SessionSource: Codable, Equatable {
    case manual
    case workSchedule(profileName: String)
    case quickTimer
    case until(date: Date, label: String?)
    case command(token: UUID, deadline: Date)

    static func validatedUntil(date: Date, label: String? = nil, now: Date, hasPermission: Bool) -> SessionSource? {
        guard hasPermission, date.timeIntervalSinceReferenceDate.isFinite, date > now else { return nil }
        return .until(date: date, label: label)
    }

    static func runningCommand(token: UUID, now: Date) -> SessionSource {
        .command(token: token, deadline: now.addingTimeInterval(24 * 60 * 60))
    }

    func endCondition(quickTimerDeadline: Date?) -> SessionEndCondition {
        switch self {
        case .until(let date, _): return .deadline(date)
        case .command(let token, let deadline): return .command(token: token, deadline: deadline)
        case .manual, .quickTimer, .workSchedule:
            return quickTimerDeadline.map { .deadline($0) } ?? .unlimited
        }
    }

    func canRestore(isActive: Bool = true, quickTimerDeadline: Date?, now: Date) -> Bool {
        if case .command = self { return false }
        guard isActive || chosenEndDate != nil else { return false }
        // A missing timer deadline is legitimate for a no-limit quick timer.
        return !endCondition(quickTimerDeadline: quickTimerDeadline).hasExpired(at: now)
    }

    /// The absolute end the user or command chose; nil for sources whose end is a quick timer.
    var chosenEndDate: Date? {
        switch self {
        case .until(let date, _), .command(_, let date): return date
        case .manual, .quickTimer, .workSchedule: return nil
        }
    }

    /// The source after the user cancels the countdown. Until and command sessions carry
    /// their own deadline, so they become manual; other sources keep their owner
    /// (a schedule-started session must still stop when the schedule ends).
    var cancellingCountdown: SessionSource {
        chosenEndDate == nil ? self : .manual
    }

    var relinquishingCommand: SessionSource {
        guard case .command(_, let deadline) = self else { return self }
        return .until(date: deadline, label: nil)
    }
}

enum SessionEndCondition: Equatable {
    case unlimited
    case deadline(Date)
    case command(token: UUID, deadline: Date)

    var deadline: Date? {
        switch self {
        case .unlimited: return nil
        case .deadline(let date), .command(_, let date): return date
        }
    }

    func hasExpired(at now: Date) -> Bool {
        guard let deadline else { return false }
        return !deadline.timeIntervalSinceReferenceDate.isFinite || deadline <= now
    }

    func matchesFinish(token: UUID) -> Bool {
        guard case .command(let owner, _) = self else { return false }
        return owner == token
    }
}
