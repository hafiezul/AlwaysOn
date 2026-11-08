import AppIntents
import Foundation

/// A Focus filter: in System Settings > Focus, add AlwaysOn to a Focus to
/// keep you online, or use a profile, while that Focus is on.
///
/// Parameters default to "no change", so a call with default values (which
/// is how the system reports a Focus without this filter, or one turning
/// off) undoes whatever an earlier Focus set up.
struct AlwaysOnFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Set AlwaysOn Behavior"
    static let description = IntentDescription(
        "Keeps you online, or switches to a profile, while this Focus is on. When the Focus turns off, a session it started stops and the previous profile returns.")

    @Parameter(title: "Keep Me Online", default: false)
    var keepOnline: Bool

    @Parameter(title: "Use Profile")
    var profile: ProfileEntity?

    var displayRepresentation: DisplayRepresentation {
        var parts: [String] = []
        if keepOnline { parts.append("Keep online") }
        if let profile { parts.append("Use \(profile.name)") }
        let subtitle = parts.isEmpty ? "No change" : parts.joined(separator: " · ")
        return DisplayRepresentation(title: "AlwaysOn", subtitle: "\(subtitle)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let state = AppState.shared else { throw ShortcutsActionError.notReady }
        state.applyFocusFilter(keepOnline: keepOnline, profileID: profile?.id)
        return .result()
    }
}
