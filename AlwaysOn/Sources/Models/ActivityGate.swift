import Foundation
import AppKit
import Combine

/// The single decision point for whether a simulation tick posts synthetic
/// input. AppState owns the persisted settings; the simulator consults the
/// gate before every tick so new suppression rules extend this type instead
/// of growing conditionals at the call site.
struct ActivityGate: Equatable {
    /// Post only when the user has produced no real input for at least the
    /// threshold. Their own activity already keeps the system and their
    /// presence apps awake, so synthetic input would only interfere.
    var idleOnlyEnabled = false

    /// Post only while at least one target app is running. Simulation with
    /// no chat or meeting app open changes nothing, so the tick is skipped.
    var requireTargetApp = false

    /// Bundle IDs counted as target apps when requireTargetApp is on
    var targetBundleIDs: Set<String> = []

    /// Minimum idle seconds before a gated tick posts. Kept at or below the
    /// smallest interval so a gated loop still sustains itself: each posted
    /// event resets the idle counter, and the next check runs one interval later.
    static let idleThreshold: TimeInterval = 30

    enum Decision: Equatable {
        case post
        case skip(SkipReason)
    }

    enum SkipReason: String, Hashable {
        case userActive, noTarget
    }

    func decision(idleSeconds: @autoclosure () -> TimeInterval, hasRunningTarget: @autoclosure () -> Bool) -> Decision {
        if idleOnlyEnabled && idleSeconds() < Self.idleThreshold { return .skip(.userActive) }
        if requireTargetApp && !hasRunningTarget() { return .skip(.noTarget) }
        return .post
    }

    func shouldPost(idleSeconds: @autoclosure () -> TimeInterval, hasRunningTarget: @autoclosure () -> Bool) -> Bool {
        decision(idleSeconds: idleSeconds(), hasRunningTarget: hasRunningTarget()) == .post
    }

}

/// A chat or meeting app that AlwaysOn can watch before simulating activity
struct TargetApp: Identifiable, Equatable {
    let bundleID: String
    let name: String

    var id: String { bundleID }

    /// Whether an app with this bundle ID is installed on this machine
    static func isInstalled(_ app: TargetApp) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) != nil
    }

    /// Workplace apps whose presence AlwaysOn is meant to protect
    static let catalog: [TargetApp] = [
        TargetApp(bundleID: "com.microsoft.teams2", name: "Microsoft Teams"),
        TargetApp(bundleID: "com.microsoft.teams", name: "Teams Classic"),
        TargetApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"),
        TargetApp(bundleID: "us.zoom.xos", name: "Zoom"),
        TargetApp(bundleID: "com.hnc.Discord", name: "Discord")
    ]
}


final class PulseLog: ObservableObject {
    enum Outcome: Hashable {
        case posted, userActive, noTarget, inputCreationFailed
        /// Simulation stopped because the Mac slept, locked, or switched users
        case systemPaused
        /// A tick found Accessibility permission revoked
        case permissionMissing
        /// The session stopped after the away limit passed with no input from the user
        case stoppedAway
        /// The session stopped because the battery reached the chosen level
        case stoppedLowBattery
    }
    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let outcome: Outcome
        var summary: String {
            switch outcome {
            case .posted: return "Input posted"
            case .userActive: return "Skipped: user active"
            case .noTarget: return "Skipped: no target app"
            case .inputCreationFailed: return "Input creation failed"
            case .systemPaused: return "Paused: Mac asleep, locked, or switched user"
            case .permissionMissing: return "Stopped: Accessibility permission missing"
            case .stoppedAway: return "Stopped: away limit reached"
            case .stoppedLowBattery: return "Stopped: low battery"
            }
        }
    }
    /// How the Pulse Log groups outcomes
    enum Category: String, CaseIterable, Identifiable {
        case posted, skipped, paused, problem

        var id: String { rawValue }

        var title: String {
            switch self {
            case .posted: return "Posted"
            case .skipped: return "Skipped"
            case .paused: return "Paused"
            case .problem: return "Problems"
            }
        }
    }

    @Published private(set) var history: [Entry] = []

    /// Recorded attempts per category since launch or the last clear
    func count(of category: Category) -> Int {
        counts.reduce(0) { $0 + ($1.key.category == category ? $1.value : 0) }
    }
    @Published private(set) var counts: [Outcome: Int] = [:]
    var latestOutcome: Outcome? { history.last?.outcome }
    func record(_ outcome: Outcome, date: Date = Date()) {
        history.append(Entry(date: date, outcome: outcome))
        if history.count > 200 { history.removeFirst(history.count - 200) }
        counts[outcome, default: 0] += 1
    }
    func clear() { history.removeAll(); counts.removeAll() }
}

extension PulseLog.Outcome {
    var category: PulseLog.Category {
        switch self {
        case .posted: return .posted
        case .userActive, .noTarget: return .skipped
        case .systemPaused: return .paused
        case .inputCreationFailed, .permissionMissing, .stoppedAway, .stoppedLowBattery: return .problem
        }
    }

    /// Why this happened, in plain words
    var explanation: String {
        switch self {
        case .posted: return "Sent simulated input to keep you active."
        case .userActive: return "You used the Mac in the last 30 seconds, so no input was needed."
        case .noTarget: return "None of your target apps were running."
        case .inputCreationFailed: return "macOS didn't create the input event."
        case .systemPaused: return "Waiting until the Mac is awake, unlocked, and back on your session."
        case .permissionMissing: return "Accessibility permission was turned off, so the session stopped."
        case .stoppedAway: return "You were away longer than your away limit, so the session stopped."
        case .stoppedLowBattery: return "The battery reached your stop level, so the session stopped."
        }
    }
}
