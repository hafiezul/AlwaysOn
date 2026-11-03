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
            }
        }
    }
    @Published private(set) var history: [Entry] = []
    @Published private(set) var counts: [Outcome: Int] = [:]
    var latestOutcome: Outcome? { history.last?.outcome }
    func record(_ outcome: Outcome, date: Date = Date()) {
        history.append(Entry(date: date, outcome: outcome))
        if history.count > 200 { history.removeFirst(history.count - 200) }
        counts[outcome, default: 0] += 1
    }
    func clear() { history.removeAll(); counts.removeAll() }
}
