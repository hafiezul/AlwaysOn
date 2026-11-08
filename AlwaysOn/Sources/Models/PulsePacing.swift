import Foundation

/// How the simulator decides when to post input
enum PulsePacing: String, CaseIterable, Identifiable {
    /// Post on a fixed interval, whatever the user is doing
    case fixed
    /// Post only once the Mac has been idle for a while, and sleep until then
    case adaptive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fixed: return "Fixed interval"
        case .adaptive: return "Adaptive"
        }
    }
}

/// How long the Mac may sit idle before adaptive pacing posts input. Chat
/// apps mark you Away after about 5 minutes (Teams, Zoom) or 10 (Slack),
/// so every choice keeps a wide margin.
enum AdaptivePostAfter: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case twoMinutes = 120
    case fourMinutes = 240

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var title: String {
        switch self {
        case .oneMinute: return "1 minute"
        case .twoMinutes: return "2 minutes (Default)"
        case .fourMinutes: return "4 minutes"
        }
    }
}

/// Low Power Mode and thermal pressure, as far as pacing cares
struct EnergyState: Equatable {
    var isLowPowerMode = false
    /// The thermal state is serious or critical
    var isThermallyConstrained = false

    var isConstrained: Bool { isLowPowerMode || isThermallyConstrained }

    /// Why the Mac wants less work, for display; nil when it doesn't
    var summary: String? {
        switch (isLowPowerMode, isThermallyConstrained) {
        case (true, true): return "Low Power Mode is on and the Mac is running hot"
        case (true, false): return "Low Power Mode is on"
        case (false, true): return "The Mac is running hot"
        case (false, false): return nil
        }
    }
}

/// When the simulator ticks next and whether a tick posts. A pure value so
/// the pacing rules are testable without timers or input events.
struct PulseSchedule: Equatable {
    var pacing: PulsePacing = .fixed
    /// The user's fixed interval, in seconds
    var interval: TimeInterval = 45
    /// Idle seconds after which adaptive pacing posts
    var postAfter: TimeInterval = AdaptivePostAfter.twoMinutes.seconds
    /// Whether to stretch the work because of Low Power Mode or heat
    var savesEnergy = false

    /// Shortest adaptive wait, so bursts of activity can't cause rapid ticks
    static let minimumDelay: TimeInterval = 5
    /// A tick this close to the threshold counts as due
    static let dueSlack: TimeInterval = 2
    /// Saving energy never stretches the fixed interval past this, unless the
    /// user already chose a longer one
    static let energySavingCap: TimeInterval = 120
    /// The screen saver must never start before adaptive pacing posts
    static let screenSaverMargin: TimeInterval = 15
    /// Floor for a post-after time shortened by the screen saver
    static let shortestPostAfter: TimeInterval = 30

    /// The fixed interval after energy saving: doubled, up to two minutes
    var effectiveInterval: TimeInterval {
        guard savesEnergy else { return interval }
        return min(interval * 2, max(interval, Self.energySavingCap))
    }

    /// Whether the user has been idle long enough for a tick to post
    func isDue(idleSeconds: TimeInterval) -> Bool {
        pacing == .fixed || idleSeconds >= postAfter - Self.dueSlack
    }

    /// Seconds until the next tick, given the idle time this tick measured
    func nextDelay(idleSeconds: TimeInterval) -> TimeInterval {
        switch pacing {
        case .fixed:
            return effectiveInterval
        case .adaptive:
            // A post resets the idle time, and a tick held back by another
            // rule (no target app) has nothing to gain from checking sooner
            guard idleSeconds.isFinite, idleSeconds >= 0, !isDue(idleSeconds: idleSeconds) else { return postAfter }
            // Otherwise wake exactly when the idle time reaches the threshold
            return max(postAfter - idleSeconds, Self.minimumDelay)
        }
    }

    /// Timer tolerance: a tenth of the delay up to 5 s, doubled while saving energy
    func tolerance(for delay: TimeInterval) -> TimeInterval {
        savesEnergy ? min(delay * 0.2, 10) : min(delay * 0.1, 5)
    }

    /// The chosen post-after time, shortened so input lands before the
    /// screen saver starts (and possibly locks the Mac)
    static func postAfter(chosen: AdaptivePostAfter, screenSaverDelay: TimeInterval?) -> TimeInterval {
        guard let screenSaverDelay, screenSaverDelay > 0 else { return chosen.seconds }
        return min(chosen.seconds, max(screenSaverDelay - screenSaverMargin, shortestPostAfter))
    }
}

// MARK: - Sleep prevention

/// What AlwaysOn keeps awake while a session is active
enum SleepPrevention: String, CaseIterable, Identifiable {
    case off
    case system
    case systemAndDisplay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .system: return "Keep Mac awake"
        case .systemAndDisplay: return "Keep Mac and display awake"
        }
    }
}

/// The power assertion AlwaysOn holds
enum PowerAssertionLevel: Equatable {
    /// The Mac doesn't idle-sleep; the display may
    case system
    /// Neither the Mac nor the display idle-sleeps
    case display
}

enum SleepPreventionPolicy {
    /// The assertion to hold right now, nil for none.
    /// - Parameters:
    ///   - setting: The user's sleep prevention choice
    ///   - pacing: Adaptive pacing lets the idle time grow past the display
    ///     sleep delay, so it keeps the display awake itself, as fixed pacing
    ///     always did by posting input every interval
    ///   - isActive: Whether a session is running (not paused or stopped)
    ///   - suspension: Why the system suspended simulation, if it did
    ///   - targetAppReady: Whether the target-app rule allows posting, so
    ///     adaptive pacing doesn't hold the display on with no chat app open
    static func requiredLevel(setting: SleepPrevention, pacing: PulsePacing, isActive: Bool,
                              suspension: SystemConditions.SuspensionReason?,
                              targetAppReady: Bool) -> PowerAssertionLevel? {
        guard isActive else { return nil }
        switch suspension {
        case .asleep?, .sessionInactive?:
            return nil
        case .screenLocked?:
            // Keep the Mac awake for long jobs, but let the lock screen go dark
            return setting == .off ? nil : .system
        case nil:
            break
        }
        if setting == .systemAndDisplay || (pacing == .adaptive && targetAppReady) { return .display }
        return setting == .system ? .system : nil
    }
}
