import SwiftUI

/// General settings pane with launch at login, activity interval, activity method, and permission status
struct GeneralSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    
    // Activity interval options in seconds
    private let intervalOptions: [(label: String, value: TimeInterval)] = [
        ("30 seconds", 30),
        ("45 seconds (Default)", 45),
        ("1 minute", 60),
        ("2 minutes", 120),
        ("5 minutes", 300)
    ]
    
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
            
            // Activity section
            Section {
                Picker("Activity Interval", selection: $appState.activityInterval) {
                    ForEach(intervalOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
                
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
                
                Picker("Auto-disable after", selection: $appState.defaultTimerDuration) {
                    ForEach(QuickTimerDuration.allCases) { duration in
                        Text(duration.title).tag(duration)
                    }
                }
                .pickerStyle(.menu)
                
                Text("Automatically pause after the selected duration. Choose 'No limit' to stay active indefinitely.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Only simulate when idle", isOn: $appState.simulateOnlyWhenIdle)

                Text("Skips simulated input whenever you produced input in the last 30 seconds, since your own activity already keeps the system awake.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Global hotkey (⌥⌘K)", isOn: $appState.globalHotKeyEnabled)

                Text("Toggles your session from any app, even with the menu closed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Activity")
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
        }
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
