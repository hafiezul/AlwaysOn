import SwiftUI

/// Main menu bar dropdown view
/// Kept minimal - all settings live in the Settings window
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var pendingProfileId: UUID?

    private var pendingProfileName: String {
        guard let pendingProfileId else { return "this profile" }
        return appState.profileManager.profiles.first(where: { $0.id == pendingProfileId })?.name ?? "this profile"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            statusHeader
            
            Divider()
                .padding(.vertical, 4)

            profileMenu
            
            Divider()
                .padding(.vertical, 4)
            
            // Main toggle button (Pause when active, Resume when paused)
            toggleButton
            
            // Permission section if needed
            if !appState.hasAccessibilityPermission {
                permissionSection
            }
            
            // Session info when active or paused with saved duration
            if appState.hasActiveOrPausedSession {
                sessionInfo
                
                // Quick timer info if active
                if appState.isQuickTimerActive {
                    quickTimerInfo
                }
            }
            
            // Stop Session button (shown for active and paused sessions, AFTER session info)
            if appState.hasActiveOrPausedSession {
                stopSessionButton
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Until, Pulse Log, Settings and Quit (available even when inactive)
            untilButton
            pulseLogButton
            settingsButton
            quitButton
        }
        .padding(.vertical, 8)
        .frame(width: 260)
        .background(MenuVisibilityReader { appState.isMenuVisible = $0 })
        .onDisappear { appState.isMenuVisible = false }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var statusHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.isActive ? Color.green : (appState.hasActiveOrPausedSession ? Color.orange : Color.gray))
                .frame(width: 8, height: 8)

            Text(appState.isActive ? "Active" : (appState.hasActiveOrPausedSession ? "Paused" : "Inactive"))
                .font(.headline)

            Spacer()

            let today = appState.onlineTimeToday
            if today > 0 {
                Text("Today \(ActivityDurationFormat.long(today))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)

        if let stop = appState.lastSafetyStop, !appState.hasActiveOrPausedSession {
            Label(stop.shortSummary, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        }
    }
    
    private var toggleButton: some View {
        Button(action: {
            appState.toggle()
        }) {
            HStack(spacing: 8) {
                Image(systemName: appState.isActive ? "pause.circle" : "play.circle")
                    .frame(width: 16)
                Text(appState.isActive ? "Pause" : (appState.hasActiveOrPausedSession ? "Resume" : "Keep Online"))
                Spacer()
                Text("⌘K")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(HoverBackground())
        .keyboardShortcut("k", modifiers: .command)
    }

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

            Button("Manage Profiles...") {
                SettingsWindowController.shared.show(appState: appState, selectedItem: .profiles)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.2")
                    .frame(width: 16)
                Text(appState.profileManager.activeProfile?.name ?? "Profile")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(HoverBackground())
    }

    private var profileSwitchConfirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.2")
                    .frame(width: 16)
                Text("Switch Profile?")
                    .font(.headline)
                Spacer()
            }

            Text("Switch to \(pendingProfileName) and stop the current session?")
                .font(.subheadline)

            Text("The current session and timer will be cleared.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Button("Cancel") {
                    pendingProfileId = nil
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Switch & Stop Session", role: .destructive) {
                    guard let pendingProfileId else { return }
                    appState.switchProfile(pendingProfileId)
                    self.pendingProfileId = nil
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private var stopSessionButton: some View {
        Button(action: {
            appState.stopSession()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "stop.circle")
                    .frame(width: 16)
                Text("Stop Session")
                    .foregroundColor(.red)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(HoverBackground())
    }
    
    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.vertical, 4)
            
            // Warning with explanation
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .frame(width: 16)
                    Text("Accessibility Required")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }
                
                Text("Grant permission below. For reinstalls, see the setup guide to remove the old entry first.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Grant Permission button (primary action)
            Button(action: {
                appState.requestPermission()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.open")
                        .frame(width: 16)
                    Text("Grant Permission")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(HoverBackground())

            // Setup guide (secondary — covers Open Settings too)
            Button(action: {
                appState.showPermissionsWindow()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield")
                        .frame(width: 16)
                    Text("Setup Guide...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(HoverBackground())
        }
    }
    
    private var sessionInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .frame(width: 16)
                    .foregroundColor(.secondary)
                Text("Session: \(formatDuration(appState.activeSessionDuration))")
                    .foregroundColor(.secondary)
                if !appState.isActive {
                    Text("(paused)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                Spacer()
            }

            if let label = appState.sessionSourceLabel {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 24)
            }

            // Until and command sessions stop at an absolute time; show it, not only the countdown
            if let endDate = appState.sessionSource?.chosenEndDate {
                Text("Ends \(endDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 24)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    
    private var quickTimerInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .frame(width: 16)
                    .foregroundColor(.orange)
                Text("Auto-pause in: \(formatDuration(appState.quickTimerRemaining))")
                    .foregroundColor(.orange)
                Spacer()
            }
            
            Button(action: {
                appState.cancelQuickTimer()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle")
                        .frame(width: 16)
                    Text("Cancel Timer")
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(HoverBackground())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
    
    private var untilButton: some View {
        Button(action: {
            UntilSessionWindowController.shared.show(appState: appState)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .frame(width: 16)
                Text("Until...")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(HoverBackground())
    }

    private var pulseLogButton: some View {
        Button(action: {
            PulseLogWindowController.shared.show(appState: appState)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .frame(width: 16)
                Text("Pulse Log...")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(HoverBackground())
    }

    private var settingsButton: some View {
        Button(action: {
            SettingsWindowController.shared.show(appState: appState)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .frame(width: 16)
                Text("Settings...")
                Spacer()
                Text("⌘,")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(HoverBackground())
        .keyboardShortcut(",", modifiers: .command)
    }
    
    private var quitButton: some View {
        Button(action: {
            NSApplication.shared.terminate(nil)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "power")
                    .frame(width: 16)
                Text("Quit AlwaysOn")
                Spacer()
                Text("⌘Q")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(HoverBackground())
        .keyboardShortcut("q", modifiers: .command)
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

/// Reports whether the menu's window is on screen. MenuBarExtra windows are
/// reused and ordered out rather than closed, so this follows the window's
/// occlusion state instead of relying on onAppear alone.
private struct MenuVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: VisibilityView, context: Context) {
        view.onChange = onChange
    }

    final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        private var token: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            guard let window else { report(false); return }
            token = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                           object: window, queue: .main) { [weak self, weak window] _ in
                self?.report(window?.occlusionState.contains(.visible) ?? false)
            }
            report(window.occlusionState.contains(.visible))
        }

        /// Deferred so state changes never happen inside a SwiftUI view update
        private func report(_ visible: Bool) {
            DispatchQueue.main.async { [weak self] in self?.onChange?(visible) }
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}

/// Provides hover highlight effect for menu items
struct HoverBackground: View {
    @State private var isHovered = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
