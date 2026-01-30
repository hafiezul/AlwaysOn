import SwiftUI

/// General settings pane with launch at login, activity interval, and permission status
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
            } header: {
                Text("Activity")
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
}

#Preview {
    GeneralSettingsPane()
        .environmentObject(AppState())
        .frame(width: 450, height: 350)
}
