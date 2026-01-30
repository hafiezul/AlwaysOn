import SwiftUI

/// About window showing app information and update status
struct AboutView: View {
    @State private var updateState: UpdateState = .idle
    @Environment(\.openURL) private var openURL
    
    enum UpdateState {
        case idle
        case checking
        case upToDate
        case available(UpdateChecker.UpdateInfo)
        case error(String)
    }
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // App icon placeholder
            Image(systemName: "circle.fill")
                .resizable()
                .frame(width: 64, height: 64)
                .foregroundColor(.accentColor)
            
            // App name
            Text("AlwaysOn")
                .font(.title)
                .fontWeight(.bold)
            
            // Version info
            Text("Version \(appVersion) (\(buildNumber))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Description
            Text("Keep your status active")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.horizontal, 20)
            
            // Update section
            updateSection
            
            Divider()
                .padding(.horizontal, 20)
            
            // Links
            HStack(spacing: 20) {
                Button("GitHub") {
                    if let url = URL(string: "https://github.com/hafiezul/AlwaysOn") {
                        openURL(url)
                    }
                }
                .buttonStyle(.link)
                
                Button("Report Issue") {
                    if let url = URL(string: "https://github.com/hafiezul/AlwaysOn/issues") {
                        openURL(url)
                    }
                }
                .buttonStyle(.link)
            }
            
            // Copyright
            Text("Copyright 2024 Hafiezul")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 300)
    }
    
    @ViewBuilder
    private var updateSection: some View {
        VStack(spacing: 8) {
            switch updateState {
            case .idle:
                Button("Check for Updates") {
                    checkForUpdates()
                }
                
            case .checking:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Checking for updates...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
            case .upToDate:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("You're up to date!")
                        .font(.caption)
                }
                
            case .available(let info):
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.blue)
                        Text("Version \(info.version) available")
                            .font(.caption)
                    }
                    
                    Button("Download Update") {
                        openURL(info.releaseURL)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                
            case .error(let message):
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("Update check failed")
                            .font(.caption)
                    }
                    Text(message)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Button("Retry") {
                        checkForUpdates()
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                }
            }
        }
    }
    
    private func checkForUpdates() {
        updateState = .checking
        
        UpdateChecker.checkForUpdate { result in
            switch result {
            case .upToDate:
                updateState = .upToDate
            case .updateAvailable(let info):
                updateState = .available(info)
            case .error(let error):
                updateState = .error(error.localizedDescription)
            }
        }
    }
}

/// Window controller for the About window
final class AboutWindowController {
    private static var windowController: NSWindowController?
    
    static func show() {
        if let existingWindow = windowController?.window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let aboutView = AboutView()
        let hostingController = NSHostingController(rootView: aboutView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "About AlwaysOn"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        
        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

#Preview {
    AboutView()
}
