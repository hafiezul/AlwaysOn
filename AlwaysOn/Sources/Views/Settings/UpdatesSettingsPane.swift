import SwiftUI
import Sparkle

/// Updates settings pane with Sparkle auto-update configuration
struct UpdatesSettingsPane: View {
    @ObservedObject private var sparkleUpdater = SparkleUpdaterManager.shared
    
    // Access the underlying updater for settings
    private var updater: SPUUpdater {
        sparkleUpdater.updater
    }
    
    var body: some View {
        Form {
            // Automatic updates section
            Section {
                Toggle("Automatically check for updates", isOn: automaticallyChecksForUpdates)
                
                Toggle("Automatically download updates", isOn: automaticallyDownloadsUpdates)
                    .disabled(!updater.automaticallyChecksForUpdates)
                
                Text("When enabled, updates will be downloaded in the background and you'll be prompted to install them.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Automatic Updates")
            }
            
            // Manual update check section
            Section {
                HStack {
                    Button("Check for Updates Now") {
                        sparkleUpdater.checkForUpdates()
                    }
                    .disabled(!sparkleUpdater.canCheckForUpdates)
                    
                    Spacer()
                    
                    if let lastCheck = sparkleUpdater.lastUpdateCheckDate {
                        Text("Last checked: \(formattedLastCheck(lastCheck))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Manual Check")
            }
            
            // Update channel section (if you want to add beta channel later)
            Section {
                Text("AlwaysOn will notify you when updates are available and let you choose when to install them.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("About Updates")
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Sparkle Bindings
    
    private var automaticallyChecksForUpdates: Binding<Bool> {
        Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
        )
    }
    
    private var automaticallyDownloadsUpdates: Binding<Bool> {
        Binding(
            get: { updater.automaticallyDownloadsUpdates },
            set: { updater.automaticallyDownloadsUpdates = $0 }
        )
    }
    
    // MARK: - Formatting
    
    /// Formats the last check date as a static, human-readable string
    private func formattedLastCheck(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
}

#Preview {
    UpdatesSettingsPane()
        .frame(width: 450, height: 300)
}
