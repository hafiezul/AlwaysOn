import Foundation
import AppKit

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

    func shouldPost(idleSeconds: TimeInterval, hasRunningTarget: Bool) -> Bool {
        idleGateOpen(idleSeconds) && targetGateOpen(hasRunningTarget)
    }

    private func idleGateOpen(_ idleSeconds: TimeInterval) -> Bool {
        !idleOnlyEnabled || idleSeconds >= Self.idleThreshold
    }

    private func targetGateOpen(_ hasRunningTarget: Bool) -> Bool {
        !requireTargetApp || hasRunningTarget
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
