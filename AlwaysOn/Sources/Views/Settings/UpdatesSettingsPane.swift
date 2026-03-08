import SwiftUI
import Sparkle

/// Updates settings pane with Sparkle auto-update configuration
struct UpdatesSettingsPane: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject private var sparkleUpdater = SparkleUpdaterManager.shared
    @State private var isCheckingManually = false
    @State private var manualUpdateInfo: UpdateChecker.UpdateInfo?
    @State private var manualStatusMessage: String?
    
    // Access the underlying updater for settings
    private var updater: SPUUpdater? {
        sparkleUpdater.updater
    }
    
    var body: some View {
        Form {
            if UpdateChecker.currentMode.usesSparkle {
                Section {
                    Toggle("Automatically check for updates", isOn: automaticallyChecksForUpdates)

                    Toggle("Automatically download updates", isOn: automaticallyDownloadsUpdates)
                        .disabled(!(updater?.automaticallyChecksForUpdates ?? false))

                    Text("When enabled, updates will be downloaded in the background and you'll be prompted to install them.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Automatic Updates")
                }

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

                Section {
                    Text("This signed build can use Sparkle for in-app updates.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("About Updates")
                }
            } else {
                Section {
                    Text("This build uses manual updates because it is not signed with Apple Developer ID.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(isCheckingManually ? "Checking..." : "Check Latest GitHub Release") {
                        checkForManualUpdate()
                    }
                    .disabled(isCheckingManually)

                    if let manualStatusMessage {
                        Text(manualStatusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let manualUpdateInfo {
                        Button("Open Release \(manualUpdateInfo.version)") {
                            openURL(manualUpdateInfo.releaseURL)
                        }
                    }
                } header: {
                    Text("Manual Updates")
                }

                Section {
                    Text("Automatic Sparkle updates are disabled for unsigned builds. Download updates from GitHub Releases and re-run the matching helper only if Accessibility access breaks.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("About Updates")
                }
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Sparkle Bindings
    
    private var automaticallyChecksForUpdates: Binding<Bool> {
        Binding(
            get: { updater?.automaticallyChecksForUpdates ?? false },
            set: { updater?.automaticallyChecksForUpdates = $0 }
        )
    }
    
    private var automaticallyDownloadsUpdates: Binding<Bool> {
        Binding(
            get: { updater?.automaticallyDownloadsUpdates ?? false },
            set: { updater?.automaticallyDownloadsUpdates = $0 }
        )
    }

    private func checkForManualUpdate() {
        isCheckingManually = true
        manualUpdateInfo = nil
        manualStatusMessage = nil

        UpdateChecker.checkForUpdate { result in
            isCheckingManually = false

            switch result {
            case .updateAvailable(let info):
                manualUpdateInfo = info
                manualStatusMessage = "Version \(info.version) is available on GitHub Releases."
            case .upToDate:
                manualStatusMessage = "You already have the latest release."
            case .error(let error):
                manualStatusMessage = error.localizedDescription
            }
        }
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
