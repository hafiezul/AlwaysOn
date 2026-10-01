import Foundation

/// The single decision point for whether a simulation tick posts synthetic
/// input. AppState owns the persisted settings; the simulator consults the
/// gate before every tick so new suppression rules extend this type instead
/// of growing conditionals at the call site.
struct ActivityGate: Equatable {
    /// Post only when the user has produced no real input for at least the
    /// threshold. Their own activity already keeps the system and their
    /// presence apps awake, so synthetic input would only interfere.
    var idleOnlyEnabled = false

    /// Minimum idle seconds before a gated tick posts. Kept at or below the
    /// smallest interval so a gated loop still sustains itself: each posted
    /// event resets the idle counter, and the next check runs one interval later.
    static let idleThreshold: TimeInterval = 30

    func shouldPost(idleSeconds: TimeInterval) -> Bool {
        !idleOnlyEnabled || idleSeconds >= Self.idleThreshold
    }
}
