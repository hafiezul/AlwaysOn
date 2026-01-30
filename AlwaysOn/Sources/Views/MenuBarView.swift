import SwiftUI

/// Main menu bar dropdown view
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    @ObservedObject private var sparkleUpdater = SparkleUpdaterManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            statusHeader
            
            Divider()
                .padding(.vertical, 4)
            
            // Main toggle button
            toggleButton
            
            // Permission section if needed
            if !appState.hasAccessibilityPermission {
                permissionSection
            }
            
            // Session info when active
            if appState.isActive {
                sessionInfo
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Settings section
            settingsSection
            
            Divider()
                .padding(.vertical, 4)
            
            // About and Quit
            aboutButton
            quitButton
        }
        .padding(.vertical, 8)
        .frame(width: 240)
        .onAppear {
            // Refresh launch at login state when menu appears
            launchAtLogin = LaunchAtLoginManager.isEnabled
        }
    }
    
    // MARK: - View Components
    
    private var statusHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            Text(appState.isActive ? "Active" : "Inactive")
                .font(.headline)
            
            Spacer()
            
            // Version badge
            Text("v\(appVersion)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
    
    private var toggleButton: some View {
        Button(action: {
            appState.toggle()
        }) {
            HStack(spacing: 8) {
                Image(systemName: appState.isActive ? "pause.circle" : "play.circle")
                    .frame(width: 16)
                Text(appState.isActive ? "Pause" : "Keep Online")
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
                
                Text("Click below to grant permission. If you reinstalled the app, remove the old entry in Settings first.")
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
            
            // Open Settings button (secondary/fallback)
            Button(action: {
                appState.openAccessibilitySettings()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "gear")
                        .frame(width: 16)
                    Text("Open Settings...")
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
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .frame(width: 16)
                .foregroundColor(.secondary)
            Text("Session: \(formatDuration(appState.activeSessionDuration))")
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Launch at Login toggle
            Button(action: {
                LaunchAtLoginManager.toggle()
                launchAtLogin = LaunchAtLoginManager.isEnabled
            }) {
                HStack(spacing: 8) {
                    Image(systemName: launchAtLogin ? "checkmark.square.fill" : "square")
                        .frame(width: 16)
                        .foregroundColor(launchAtLogin ? .accentColor : .secondary)
                    Text("Launch at Login")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(HoverBackground())
            
            // Check for Updates (Sparkle)
            Button(action: {
                sparkleUpdater.checkForUpdates()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .frame(width: 16)
                    Text("Check for Updates...")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(HoverBackground())
            .disabled(!sparkleUpdater.canCheckForUpdates)
        }
    }
    
    private var aboutButton: some View {
        Button(action: {
            AboutWindowController.show()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .frame(width: 16)
                Text("About AlwaysOn")
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
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    
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
