import AppIntents
import Foundation

// Shortcuts.app actions. Each one drives the same AppState entry points as
// the alwayson:// URL scheme, so permission handling and session rules match.

enum ShortcutsActionError: Error, CustomLocalizedStringResourceConvertible {
    case notReady
    case permissionMissing
    case timeInPast
    case profileNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady: return "AlwaysOn is still starting. Try again in a moment."
        case .permissionMissing: return "AlwaysOn needs Accessibility permission. Grant it in System Settings, then try again."
        case .timeInPast: return "Choose a time in the future."
        case .profileNotFound: return "That profile no longer exists."
        }
    }
}

@MainActor
private func runningAppState() throws -> AppState {
    guard let state = AppState.shared else { throw ShortcutsActionError.notReady }
    return state
}

@MainActor
private func requirePermission(_ state: AppState) throws {
    state.accessibilityPermission.refresh()
    guard state.hasAccessibilityPermission else { throw ShortcutsActionError.permissionMissing }
}

struct KeepOnlineIntent: AppIntent {
    static let title: LocalizedStringResource = "Keep Online"
    static let description = IntentDescription("Starts an AlwaysOn session. Give a number of minutes to stop automatically, or leave it empty for no limit.")

    @Parameter(title: "Minutes", inclusiveRange: (1, 1440))
    var minutes: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Keep online for \(\.$minutes) minutes")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = try runningAppState()
        try requirePermission(state)
        if let minutes {
            state.applyURLCommand(.timer(minutes: minutes))
            return .result(dialog: "Keeping you online for \(minutes) minutes.")
        }
        state.applyURLCommand(.start)
        return .result(dialog: "Keeping you online.")
    }
}

struct KeepOnlineUntilIntent: AppIntent {
    static let title: LocalizedStringResource = "Keep Online Until"
    static let description = IntentDescription("Starts an AlwaysOn session that stops at the time you choose, even if you pause it.")

    @Parameter(title: "End Time")
    var endTime: Date

    @Parameter(title: "Label")
    var label: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Keep online until \(\.$endTime)") {
            \.$label
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = try runningAppState()
        try requirePermission(state)
        guard endTime > Date() else { throw ShortcutsActionError.timeInPast }
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state.startUntil(date: endTime, label: trimmed?.isEmpty == false ? trimmed : nil) else {
            throw ShortcutsActionError.timeInPast
        }
        return .result(dialog: "Keeping you online until \(endTime.formatted(date: .omitted, time: .shortened)).")
    }
}

struct StopSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Session"
    static let description = IntentDescription("Stops the current AlwaysOn session and clears its timer.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = try runningAppState()
        let hadSession = state.hasActiveOrPausedSession
        state.applyURLCommand(.stop)
        return .result(dialog: hadSession ? "Stopped AlwaysOn." : "AlwaysOn wasn't running.")
    }
}

struct ToggleSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause or Resume"
    static let description = IntentDescription("Pauses a running AlwaysOn session, or starts or resumes one.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let state = try runningAppState()
        if !state.isActive { try requirePermission(state) }
        state.applyURLCommand(.toggle)
        return .result(value: state.isActive, dialog: state.isActive ? "AlwaysOn is active." : "AlwaysOn is paused.")
    }
}

struct PauseForIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause For"
    static let description = IntentDescription("Pauses a running AlwaysOn session and resumes it after the minutes you choose. Leave minutes empty to pause until you resume.")

    @Parameter(title: "Minutes", inclusiveRange: (1, 1440))
    var minutes: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Pause for \(\.$minutes) minutes")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = try runningAppState()
        guard state.isActive else { return .result(dialog: "AlwaysOn isn't running.") }
        state.applyURLCommand(.pause(minutes: minutes))
        guard let resumeAt = state.autoResumeAt else { return .result(dialog: "AlwaysOn is paused.") }
        return .result(dialog: "Paused until \(resumeAt.formatted(date: .omitted, time: .shortened)).")
    }
}

struct GetStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Status"
    static let description = IntentDescription("Returns whether AlwaysOn is keeping you online right now.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let state = try runningAppState()
        return .result(value: state.isActive, dialog: IntentDialog(stringLiteral: state.statusSummary))
    }
}

// MARK: - Profiles

struct ProfileEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Profile"
    static let defaultQuery = ProfileQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ProfileQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ProfileEntity] {
        try await allProfiles().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ProfileEntity] {
        try await allProfiles()
    }

    private func allProfiles() async throws -> [ProfileEntity] {
        try await MainActor.run {
            try runningAppState().profileManager.profiles.map { ProfileEntity(id: $0.id, name: $0.name) }
        }
    }
}

struct SwitchProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Profile"
    static let description = IntentDescription("Switches to another AlwaysOn profile. Switching stops the current session.")

    @Parameter(title: "Profile")
    var profile: ProfileEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Switch to \(\.$profile)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = try runningAppState()
        guard state.profileManager.profiles.contains(where: { $0.id == profile.id }) else {
            throw ShortcutsActionError.profileNotFound
        }
        state.switchProfile(profile.id)
        return .result(dialog: "Switched to \(profile.name).")
    }
}

// MARK: - Suggested shortcuts

struct AlwaysOnShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: KeepOnlineIntent(), phrases: [
            "Keep me online with \(.applicationName)",
            "Start \(.applicationName)"
        ])
        AppShortcut(intent: StopSessionIntent(), phrases: [
            "Stop \(.applicationName)"
        ])
        AppShortcut(intent: GetStatusIntent(), phrases: [
            "Is \(.applicationName) on",
            "\(.applicationName) status"
        ])
    }
}
