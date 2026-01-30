import SwiftUI

/// Main menu bar dropdown view
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    @State private var updateState: UpdateCheckState = .idle
    @Environment(\.openURL) private var openURL
    
    enum UpdateCheckState: Equatable {
        case idle
        case checking
        case upToDate
        case available(String, URL)
        case error
        
        static func == (lhs: UpdateCheckState, rhs: UpdateCheckState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.checking, .checking), (.upToDate, .upToDate), (.error, .error):
                return true
            case let (.available(v1, u1), .available(v2, u2)):
                return v1 == v2 && u1 == u2
            default:
                return false
            }
        }
    }
    
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
            
            // Check for Updates
            Button(action: {
                checkForUpdates()
            }) {
                HStack(spacing: 8) {
                    Group {
                        switch updateState {
                        case .checking:
                            ProgressView()
                                .scaleEffect(0.6)
                        case .upToDate:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        case .available:
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.blue)
                        case .error:
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.yellow)
                        case .idle:
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .frame(width: 16)
                    
                    switch updateState {
                    case .checking:
                        Text("Checking...")
                    case .upToDate:
                        Text("Up to Date")
                    case .available(let version, _):
                        Text("v\(version) Available")
                            .foregroundColor(.blue)
                    case .error:
                        Text("Check Failed")
                    case .idle:
                        Text("Check for Updates")
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(HoverBackground())
            .disabled(updateState == .checking)
            
            // Download button if update available
            if case .available(_, let url) = updateState {
                Button(action: {
                    openURL(url)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.to.line")
                            .frame(width: 16)
                        Text("Download Update")
                            .fontWeight(.medium)
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
    
    private func checkForUpdates() {
        updateState = .checking
        
        UpdateChecker.checkForUpdate { result in
            switch result {
            case .upToDate:
                updateState = .upToDate
                // Reset to idle after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if case .upToDate = updateState {
                        updateState = .idle
                    }
                }
            case .updateAvailable(let info):
                updateState = .available(info.version, info.releaseURL)
            case .error:
                updateState = .error
                // Reset to idle after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if case .error = updateState {
                        updateState = .idle
                    }
                }
            }
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
