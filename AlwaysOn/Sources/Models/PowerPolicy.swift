import Foundation

/// System states in which synthetic input cannot help the user's presence.
/// AppState feeds these from SystemEventMonitor and suspends the simulator
/// while any applicable condition holds, instead of waking the CPU to post
/// input nobody can receive.
struct SystemConditions: Equatable {
    /// The Mac is going to sleep or is asleep
    var isAsleep = false
    /// Another user's session is on the console (fast user switching)
    var isSessionInactive = false
    /// The login window covers this session
    var isScreenLocked = false

    enum SuspensionReason: Equatable {
        case asleep, sessionInactive, screenLocked
    }

    /// Why simulation should be suspended, or nil when it may run.
    /// Sleep and a switched-out session always suspend. A locked screen
    /// suspends only when the user chose to pause while locked, because some
    /// presence apps keep showing Available on a locked Mac with recent input.
    func suspensionReason(pauseWhileLocked: Bool) -> SuspensionReason? {
        if isAsleep { return .asleep }
        if isSessionInactive { return .sessionInactive }
        if isScreenLocked && pauseWhileLocked { return .screenLocked }
        return nil
    }
}

/// Decides when the session heartbeat must next run. The heartbeat refreshes
/// on-screen time and expires deadlines; between those moments nothing
/// changes, so the planner returns the longest safe delay instead of a fixed
/// one-second cadence.
enum HeartbeatPlanner {
    /// Seconds remaining below which the menu bar shows a seconds countdown
    static let secondsCountdownThreshold: TimeInterval = 60

    /// A small lead past each boundary so the tick lands after the change
    static let boundaryLead: TimeInterval = 0.05

    /// - Parameters:
    ///   - now: The current time
    ///   - deadline: When the session ends, if it has an end
    ///   - isRunning: Whether simulation is active (the menu bar shows the countdown only then)
    ///   - isMenuVisible: Whether the menu, which shows seconds, is on screen
    ///   - showsMenuBarCountdown: Whether the menu bar item shows time left
    /// - Returns: Seconds until the next tick, or nil when no tick is needed
    static func nextTickDelay(now: Date, deadline: Date?, isRunning: Bool, isMenuVisible: Bool,
                              showsMenuBarCountdown: Bool = true) -> TimeInterval? {
        let remaining = deadline.map { $0.timeIntervalSince(now) }
        if let remaining, remaining <= 0 { return 0 }

        // The open menu shows elapsed and remaining time to the second
        if isMenuVisible && (isRunning || deadline != nil) { return 1 }

        guard let remaining else { return nil }

        // With no countdown on screen, only the deadline itself matters
        guard isRunning && showsMenuBarCountdown else { return remaining }

        if remaining <= secondsCountdownThreshold { return 1 }

        // The menu bar label shows whole minutes, rounded. Wake when the
        // rounded value changes or when the seconds countdown begins.
        let shownMinutes = (remaining / 60).rounded()
        let nextLabelChange = (shownMinutes - 0.5) * 60
        let boundary = max(nextLabelChange, secondsCountdownThreshold)
        return max(remaining - boundary + boundaryLead, boundaryLead)
    }

    /// Timer tolerance that lets macOS coalesce wake-ups without visibly
    /// delaying the label: a tenth of the delay, between 0.1 and 5 seconds.
    static func tolerance(for delay: TimeInterval) -> TimeInterval {
        min(max(delay * 0.1, 0.1), 5)
    }
}

/// What the menu bar item shows next to its status icon
enum MenuBarLabelStyle: String, CaseIterable, Identifiable {
    case iconOnly
    case iconAndTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconOnly: return "Icon only"
        case .iconAndTime: return "Icon and time left"
        }
    }

    /// The countdown text for the menu bar, nil when nothing should show.
    /// Whole minutes, rounded, above a minute; seconds in the final minute.
    func timeText(remaining: TimeInterval, isTimerRunning: Bool) -> String? {
        guard self == .iconAndTime, isTimerRunning, remaining > 0 else { return nil }
        if remaining < HeartbeatPlanner.secondsCountdownThreshold { return "\(Int(remaining))s" }
        return "\(Int((remaining / 60).rounded()))m"
    }
}
