import SwiftUI

/// The menu bar window: status first, one primary action, quick durations,
/// recent activity, then navigation. Settings live in the Settings window.
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var pendingProfileId: UUID?

    private var pendingProfileName: String {
        guard let pendingProfileId else { return "this profile" }
        return appState.profileManager.profiles.first(where: { $0.id == pendingProfileId })?.name ?? "this profile"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SessionStatusCard()
                .padding(.horizontal, 8)
                .padding(.top, 8)

            notices
                .padding(.horizontal, MenuMetrics.inset)
                .padding(.top, 6)

            if !appState.hasAccessibilityPermission {
                permissionCallout
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
            }

            primaryControls
                .padding(.horizontal, MenuMetrics.inset)
                .padding(.top, 10)

            timeChips
                .padding(.horizontal, MenuMetrics.inset)
                .padding(.top, 10)
                .padding(.bottom, 8)

            Divider().padding(.vertical, 4)

            PulseStrip(pulseLog: appState.pulseLog) {
                PulseLogWindowController.shared.show(appState: appState)
            }

            Divider().padding(.vertical, 4)

            profileMenu
            MenuRow(title: "Keep Online Until…", systemImage: "calendar") {
                UntilSessionWindowController.shared.show(appState: appState)
            }
            MenuRow(title: "Settings…", systemImage: "gearshape", hint: "⌘,") {
                SettingsWindowController.shared.show(appState: appState)
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider().padding(.vertical, 4)

            MenuRow(title: "Quit AlwaysOn", systemImage: "power", hint: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.bottom, 6)
        .frame(width: MenuMetrics.width)
        .background(MenuVisibilityReader { appState.isMenuVisible = $0 })
        .onDisappear { appState.isMenuVisible = false }
    }

    // MARK: - Notices

    /// Context that explains the state: why a session ended, what is holding
    /// simulation back, and what the work hours schedule does next
    @ViewBuilder
    private var notices: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let stop = appState.lastAutoStop, !appState.hasActiveOrPausedSession {
                NoticeRow(text: stop.shortSummary, systemImage: stop.symbol, tint: .orange)
            }
            if let pending = appState.pendingNetworkProfileId,
               let name = appState.profileManager.profiles.first(where: { $0.id == pending })?.name {
                NoticeRow(text: "Switches to \(name) when this session ends", systemImage: "wifi")
            } else if let change = appState.lastNetworkSwitch, !appState.hasActiveOrPausedSession {
                NoticeRow(text: change.summary, systemImage: "wifi")
            }
            if let name = appState.focusRestoreProfileName, appState.hasActiveOrPausedSession {
                NoticeRow(text: "Switches back to \(name) when this session ends", systemImage: "moon.circle")
            }
            if appState.isActive, appState.systemSuspension != nil {
                NoticeRow(text: "Paused while the Mac is locked or asleep", systemImage: "moon.zzz")
            } else if appState.isActive, appState.requireTargetApp,
                      appState.pulseLog.latestOutcome == .noTarget {
                NoticeRow(text: "Waiting for a target app to open", systemImage: "app.dashed")
            }
            if let hint = appState.workScheduleManager.schedule.menuHint(now: Date()) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    NoticeRow(text: hint, systemImage: "calendar.badge.clock")
                    switch appState.todayScheduleAction {
                    case .skip?:
                        Button("Skip Today") { appState.setWorkHoursSkipped(true) }
                            .buttonStyle(.link)
                            .font(.caption)
                            .help("No work hours today. Ends a session that work hours started.")
                    case .undoSkip?:
                        Button("Undo") { appState.setWorkHoursSkipped(false) }
                            .buttonStyle(.link)
                            .font(.caption)
                            .help("Bring back today's work hours")
                    case nil:
                        EmptyView()
                    }
                }
            }
        }
    }

    private var permissionCallout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility permission needed")
                        .font(.callout.weight(.medium))
                    Text("AlwaysOn can't send input without it. After a reinstall, remove the old entry first.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Button("Grant Permission") { appState.requestPermission() }
                    .buttonStyle(ActionButtonStyle(kind: .prominent, compact: true))
                Button("Setup Guide…") { appState.showPermissionsWindow() }
                    .buttonStyle(ActionButtonStyle(compact: true))
            }
            .padding(.leading, 22)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.yellow.opacity(0.12))
        )
    }

    // MARK: - Primary controls

    private var primaryTitle: String {
        if appState.isActive { return "Pause" }
        return appState.hasActiveOrPausedSession ? "Resume" : "Keep Online"
    }

    private var primarySymbol: String {
        appState.isActive ? "pause.fill" : "play.fill"
    }

    @ViewBuilder
    private var primaryControls: some View {
        HStack(spacing: 8) {
            primaryButton

            if appState.isActive {
                pauseForMenu
            }

            if appState.hasActiveOrPausedSession {
                Button(role: .destructive) {
                    appState.stopSession()
                } label: {
                    Image(systemName: "stop.fill")
                        .foregroundColor(.red)
                        .frame(width: 18)
                }
                .buttonStyle(ActionButtonStyle())
                .help("Stop Session")
                .accessibilityLabel("Stop Session")
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        // Starting is the call to action; pausing a running session is quieter
        Button { appState.toggle() } label: {
            Label(primaryTitle, systemImage: primarySymbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ActionButtonStyle(kind: appState.isActive ? .plain : .prominent))
        .keyboardShortcut("k", modifiers: .command)
        .help(appState.globalHotKeyEnabled && !appState.isHotKeyUnavailable
              ? "\(primaryTitle) (⌘K, or \(appState.globalHotKey.displayString) from any app)"
              : "\(primaryTitle) (⌘K)")
    }

    /// Pause with a scheduled resume, for a break or lunch
    private var pauseForMenu: some View {
        Menu {
            Text("Pause, then resume on its own")
            ForEach(Self.pauseOptions) { option in
                Button("Pause for \(option.spoken)") {
                    appState.pause(for: TimeInterval(option.minutes * 60))
                }
            }
        } label: {
            Image(systemName: "timer")
                .frame(width: 18)
        }
        .menuIndicator(.hidden)
        .buttonStyle(ActionButtonStyle())
        .fixedSize()
        .help("Pause for…")
        .accessibilityLabel("Pause for a set time")
    }

    private static let pauseOptions = [
        ChipOption(title: "15m", spoken: "15 minutes", minutes: 15),
        ChipOption(title: "30m", spoken: "30 minutes", minutes: 30),
        ChipOption(title: "1h", spoken: "1 hour", minutes: 60),
        ChipOption(title: "2h", spoken: "2 hours", minutes: 120)
    ]

    // MARK: - Quick durations

    private struct ChipOption: Identifiable {
        let title: String
        let spoken: String
        let minutes: Int
        var id: Int { minutes }
    }

    private static let startOptions = [
        ChipOption(title: "30m", spoken: "30 minutes", minutes: 30),
        ChipOption(title: "1h", spoken: "1 hour", minutes: 60),
        ChipOption(title: "2h", spoken: "2 hours", minutes: 120),
        ChipOption(title: "4h", spoken: "4 hours", minutes: 240)
    ]

    private static let addOptions = [
        ChipOption(title: "+15m", spoken: "15 minutes", minutes: 15),
        ChipOption(title: "+30m", spoken: "30 minutes", minutes: 30),
        ChipOption(title: "+1h", spoken: "1 hour", minutes: 60),
        ChipOption(title: "+2h", spoken: "2 hours", minutes: 120)
    ]

    /// Idle: start a timed session. Timed session: add time. Unlimited
    /// session: give it an end.
    private var chipMode: (heading: String, options: [ChipOption], verb: String) {
        if !appState.hasActiveOrPausedSession { return ("Keep online for", Self.startOptions, "Keep online for") }
        if appState.sessionDeadline != nil { return ("Add time", Self.addOptions, "Add") }
        return ("Stop after", Self.startOptions, "Stop after")
    }

    private var timeChips: some View {
        let mode = chipMode
        let hasSession = appState.hasActiveOrPausedSession
        return VStack(alignment: .leading, spacing: 5) {
            Text(mode.heading)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                ForEach(mode.options) { option in
                    TimeChip(title: option.title, accessibilityText: "\(mode.verb) \(option.spoken)") {
                        if hasSession {
                            appState.addTime(TimeInterval(option.minutes * 60))
                        } else {
                            appState.startWithQuickTimer(.custom(minutes: option.minutes))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Profiles

    @ViewBuilder
    private var profileMenu: some View {
        if pendingProfileId != nil {
            profileSwitchConfirmation
        } else {
            profileSelectionMenu
        }
    }

    private var profileSelectionMenu: some View {
        Menu {
            ForEach(appState.profileManager.profiles) { profile in
                Button {
                    if appState.hasActiveOrPausedSession {
                        pendingProfileId = profile.id
                    } else {
                        appState.switchProfile(profile.id)
                    }
                } label: {
                    Label(profile.name, systemImage: profile.id == appState.profileManager.activeProfileId ? "checkmark" : "circle")
                }
            }

            Divider()

            Button("Manage Profiles…") {
                SettingsWindowController.shared.show(appState: appState, selectedItem: .profiles)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.2")
                    .frame(width: MenuMetrics.iconWidth)
                    .foregroundColor(.secondary)
                Text("Profile")
                Spacer(minLength: 8)
                Text(appState.profileManager.activeProfile?.name ?? "Default")
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, MenuMetrics.inset)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(MenuRowButtonStyle())
    }

    private var profileSwitchConfirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Switch to \(pendingProfileName)?")
                .font(.callout.weight(.medium))

            Text("This stops the current session and clears its timer.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Button("Cancel") {
                    pendingProfileId = nil
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Switch & Stop", role: .destructive) {
                    guard let pendingProfileId else { return }
                    appState.switchProfile(pendingProfileId)
                    self.pendingProfileId = nil
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal, 8)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
