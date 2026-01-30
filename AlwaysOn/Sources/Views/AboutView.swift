import SwiftUI

/// About window showing app information and update status
struct AboutView: View {
    @ObservedObject private var sparkleUpdater = SparkleUpdaterManager.shared
    @Environment(\.openURL) private var openURL
    
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
            Button("Check for Updates...") {
                sparkleUpdater.checkForUpdates()
            }
            .disabled(!sparkleUpdater.canCheckForUpdates)
            
            if let lastCheck = sparkleUpdater.lastUpdateCheckDate {
                Text("Last checked: \(lastCheck, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
