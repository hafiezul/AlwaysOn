import SwiftUI

/// Main menu bar dropdown view
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            statusHeader
            
            Divider()
            
            // Main toggle
            toggleButton
            
            // Permission warning if needed
            if !appState.hasAccessibilityPermission {
                permissionWarning
            }
            
            // Session info when active
            if appState.isActive {
                sessionInfo
            }
            
            Divider()
            
            // Quit button
            quitButton
        }
    }
    
    // MARK: - View Components
    
    private var statusHeader: some View {
        HStack {
            Circle()
                .fill(appState.isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            Text(appState.isActive ? "Active" : "Inactive")
                .font(.headline)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private var toggleButton: some View {
        Button(action: {
            appState.toggle()
        }) {
            HStack {
                Image(systemName: appState.isActive ? "pause.circle" : "play.circle")
                Text(appState.isActive ? "Pause" : "Keep Online")
                Spacer()
                if appState.isActive {
                    Text("On")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .keyboardShortcut("k", modifiers: .command)
    }
    
    private var permissionWarning: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text("Accessibility Required")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            Button(action: {
                appState.openAccessibilitySettings()
            }) {
                HStack {
                    Image(systemName: "gear")
                    Text("Open Settings")
                    Spacer()
                }
            }
            .padding(.bottom, 4)
        }
    }
    
    private var sessionInfo: some View {
        HStack {
            Image(systemName: "clock")
                .foregroundColor(.secondary)
            Text("Session: \(formatDuration(appState.activeSessionDuration))")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    
    private var quitButton: some View {
        Button(action: {
            NSApplication.shared.terminate(nil)
        }) {
            HStack {
                Image(systemName: "power")
                Text("Quit AlwaysOn")
                Spacer()
                Text("Q")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
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

#Preview {
    MenuBarView()
        .environmentObject(AppState())
        .frame(width: 220)
}
