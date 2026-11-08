import AppKit
import SwiftUI

/// General settings pane with launch at login, activity interval, activity method, and permission status
struct GeneralSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    
    @State private var cliInstallation = CLIInstallation()
    @State private var cliStatus: CLIInstallation.Status = .absent
    @State private var cliVersion: String?
    @State private var cliCanUninstall = false
    @State private var cliError: String?

    // Activity interval options in seconds
    private let intervalOptions: [(label: String, value: TimeInterval)] = [
        ("30 seconds", 30),
        ("45 seconds (Default)", 45),
        ("1 minute", 60),
        ("2 minutes", 120),
        ("5 minutes", 300)
    ]

    /// Preset tag matching the current interval, nil when it is a custom value
    private var intervalPickerSelection: Binding<TimeInterval?> {
        Binding(
            get: { intervalOptions.first { $0.value == appState.activityInterval }?.value },
            set: { if let value = $0 { appState.activityInterval = value } }
        )
    }

    /// Editing surface for the custom interval, clamped on commit
    private var customIntervalSeconds: Binding<Int> {
        Binding(
            get: { Int(appState.activityInterval) },
            set: { appState.activityInterval = TimeInterval(min(max($0, 10), 3600)) }
        )
    }

    /// Preset tag matching the current auto-disable duration, nil when custom
    private var timerPickerSelection: Binding<QuickTimerDuration?> {
        Binding(
            get: { QuickTimerDuration.allCases.first { $0 == appState.defaultTimerDuration } },
            set: { if let duration = $0 { appState.defaultTimerDuration = duration } }
        )
    }

    /// Editing surface for the custom duration in minutes, clamped on commit
    private var customTimerMinutes: Binding<Int> {
        Binding(
            get: {
                if case .custom(let minutes) = appState.defaultTimerDuration { return minutes }
                return Int((appState.defaultTimerDuration.seconds ?? 0) / 60)
            },
            set: {
                let clamped = min(max($0, QuickTimerDuration.customMinutesRange.lowerBound),
                                  QuickTimerDuration.customMinutesRange.upperBound)
                appState.defaultTimerDuration = .custom(minutes: clamped)
            }
        )
    }
    
    var body: some View {
        Form {
            // Startup section
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        LaunchAtLoginManager.isEnabled = newValue
                    }
            } header: {
                Text("Startup")
            }
            
            commandLineToolSection

            // Activity section
            Section {
                Picker("Activity Interval", selection: intervalPickerSelection) {
                    ForEach(intervalOptions, id: \.value) { option in
                        Text(option.label).tag(option.value as TimeInterval?)
                    }
                    Text("Custom…").tag(nil as TimeInterval?)
                }
                .pickerStyle(.menu)

                if intervalPickerSelection.wrappedValue == nil {
                    HStack {
                        Text("Seconds")
                        Spacer()
                        TextField(value: customIntervalSeconds, format: .number.grouping(.never)) {
                            Text("10-3600")
                        }
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                    }
                }

                Text("How often AlwaysOn simulates activity to keep your status active.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Activity Method", selection: $appState.activityMethod) {
                    ForEach(ActivityMethod.allCases) { method in
                        Label(method.title, systemImage: method.systemImage)
                            .tag(method)
                    }
                }
                .pickerStyle(.menu)
                
                Text(appState.activityMethod.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Auto-disable after", selection: timerPickerSelection) {
                    ForEach(QuickTimerDuration.allCases) { duration in
                        Text(duration.title).tag(duration as QuickTimerDuration?)
                    }
                    Text("Custom…").tag(nil as QuickTimerDuration?)
                }
                .pickerStyle(.menu)

                if timerPickerSelection.wrappedValue == nil {
                    HStack {
                        Text("Minutes")
                        Spacer()
                        TextField(value: customTimerMinutes, format: .number.grouping(.never)) {
                            Text("1-1440")
                        }
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                    }
                }
                
                Text("Automatically pause after the selected duration. Choose 'No limit' to stay active indefinitely.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Only simulate when idle", isOn: $appState.simulateOnlyWhenIdle)

                Text("Skips simulated input whenever you produced input in the last 30 seconds, since your own activity already keeps the system awake.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Pause while screen is locked", isOn: $appState.pauseWhileScreenLocked)

                Text("Most chat apps show you as Away on a locked Mac anyway, and simulated input would keep waking the display. Simulation always pauses while the Mac sleeps or another user is switched in, and resumes on its own.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Global hotkey (⌥⌘K)", isOn: $appState.globalHotKeyEnabled)

                Text("Toggles your session from any app, even with the menu closed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Activity")
            }
            
            // Safety section
            Section {
                Picker("Stop after I'm away for", selection: $appState.awayLimit) {
                    ForEach(AwayLimit.allCases) { limit in
                        Text(limit.title).tag(limit)
                    }
                }
                .pickerStyle(.menu)

                Text("Ends a session once you haven't touched the keyboard or mouse for this long, so a forgotten session doesn't run overnight. AlwaysOn's own input doesn't count.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Stop on low battery", selection: $appState.batteryStopThreshold) {
                    ForEach(BatteryStopThreshold.allCases) { threshold in
                        Text(threshold.title).tag(threshold)
                    }
                }
                .pickerStyle(.menu)

                Text("Ends a session when the battery reaches this level while unplugged. Has no effect on Macs without a battery.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Safety")
            }

            // Target app section
            Section {
                Toggle("Only while a target app is running", isOn: $appState.requireTargetApp)

                if appState.requireTargetApp {
                    ForEach(TargetApp.catalog) { app in
                        Toggle(isOn: targetAppBinding(app)) {
                            HStack {
                                Text(app.name)
                                if !TargetApp.isInstalled(app) {
                                    Text("(not installed)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                Text("Skips simulated input while none of the selected apps are running. The session stays active and resumes simulating as soon as one starts.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Target Apps")
            }
            
            // Permission status section
            Section {
                HStack {
                    Label {
                        Text("Accessibility")
                    } icon: {
                        Image(systemName: appState.hasAccessibilityPermission ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(appState.hasAccessibilityPermission ? .green : .red)
                    }
                    
                    Spacer()
                    
                    if appState.hasAccessibilityPermission {
                        Text("Granted")
                            .foregroundColor(.secondary)
                    } else {
                        Button("Grant") {
                            appState.requestPermission()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                if !appState.hasAccessibilityPermission {
                    Text("Accessibility permission is required for AlwaysOn to simulate activity.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Open System Settings") {
                        appState.openAccessibilitySettings()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = LaunchAtLoginManager.isEnabled
            refreshCLIInstallation()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshCLIInstallation()
        }
    }
    
    private var commandLineToolSection: some View {
        Section {
            Text(cliStatusDescription)
                .textSelection(.enabled)
            LabeledContent("Bundled Version / Build", value: cliVersion ?? "Unavailable")
            LabeledContent("Command Path") {
                Text(cliInstallation.linkURL.path)
                    .textSelection(.enabled)
            }
            Text("The CLI ships with this app and updates with it.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                switch cliStatus {
                case .absent:
                    Button("Install") { performCLIAction { try cliInstallation.install() } }
                case .current:
                    Button("Uninstall") { performCLIAction { try cliInstallation.uninstall() } }
                case .anotherApp:
                    Button("Use This App") { performCLIAction { try cliInstallation.install() } }
                case .brokenOwnedLink:
                    Button("Repair") { performCLIAction { try cliInstallation.install() } }
                    Button("Uninstall") { performCLIAction { try cliInstallation.uninstall() } }
                        .disabled(!cliCanUninstall)
                case .missingBundledCLI:
                    Button("Install") {}.disabled(true)
                    Button("Uninstall") { performCLIAction { try cliInstallation.uninstall() } }
                        .disabled(!cliCanUninstall)
                case .conflict:
                    Button("Install") {}.disabled(true)
                    Button("Uninstall") {}.disabled(true)
                }
            }

            if let cliError {
                Text(cliError)
                    .foregroundColor(.red)
                    .textSelection(.enabled)
                    .accessibilityLabel("Command line tool error: \(cliError)")
            }

            Text("Uses ~/.local/bin. Your shell may need PATH configuration.")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Copy PATH Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(#"export PATH="$HOME/.local/bin:$PATH""#, forType: .string)
            }
        } header: {
            Text("Command Line Tool")
        }
    }

    private var cliStatusDescription: String {
        switch cliStatus {
        case .absent:
            return "Not installed."
        case .current:
            return "Installed for this app."
        case .anotherApp(let appURL):
            return "Installed for a different copy at \(appURL.path). Use This App to replace that link."
        case .brokenOwnedLink:
            return "This app's command link is broken. Repair it or uninstall it."
        case .missingBundledCLI:
            return "Command line tool unavailable. Reinstall the full AlwaysOn app to restore the bundled CLI."
        case .conflict:
            return "Another file or command exists at this path. AlwaysOn will preserve it. Installation and removal are disabled."
        }
    }

    private func refreshCLIInstallation() {
        cliStatus = cliInstallation.status
        cliVersion = cliInstallation.version
        cliCanUninstall = cliInstallation.canUninstall
    }

    private func performCLIAction(_ action: () throws -> Void) {
        cliError = nil
        do {
            try action()
        } catch {
            cliError = error.localizedDescription
        }
        refreshCLIInstallation()
    }

    private func targetAppBinding(_ app: TargetApp) -> Binding<Bool> {
        Binding(
            get: { appState.targetApps.contains(app.bundleID) },
            set: { selected in
                if selected {
                    appState.targetApps.insert(app.bundleID)
                } else {
                    appState.targetApps.remove(app.bundleID)
                }
            }
        )
    }
}

#Preview {
    GeneralSettingsPane()
        .environmentObject(AppState())
        .frame(width: 450, height: 450)
}
