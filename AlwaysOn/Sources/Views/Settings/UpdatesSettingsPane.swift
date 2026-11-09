import SwiftUI

/// Updates settings: Sparkle auto-updates in release builds, a manual GitHub
/// release check in local builds that carry no update key.
struct UpdatesSettingsPane: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        if updater.isConfigured {
            AutomaticUpdatesForm(updater: updater)
        } else {
            ManualUpdatesForm()
        }
    }
}

// MARK: - Automatic (Sparkle)

private struct AutomaticUpdatesForm: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        Form {
            Section {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)

                Toggle("Download and install updates automatically", isOn: $updater.automaticallyDownloadsUpdates)
                    .disabled(!updater.automaticallyChecksForUpdates)

                HStack {
                    Button("Check for Updates…") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)

                    Spacer()

                    Text(lastCheckedText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Automatic Updates")
            } footer: {
                Text("AlwaysOn relaunches to finish installing an update.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Text("Updates come from GitHub Releases. AlwaysOn installs one only after checking its signature, and every release is signed with the same certificate, so Accessibility access carries over to the new version.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("About Updates")
            }
        }
        .formStyle(.grouped)
    }

    private var lastCheckedText: String {
        guard let date = updater.lastUpdateCheckDate else { return "Not checked yet" }
        return "Last checked \(date.formatted(.relative(presentation: .named)))"
    }
}

// MARK: - Manual (local builds)

private struct ManualUpdatesForm: View {
    @Environment(\.openURL) private var openURL
    @State private var isChecking = false
    @State private var updateInfo: UpdateChecker.UpdateInfo?
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section {
                Text("This build can't update itself. Release builds from GitHub update automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(isChecking ? "Checking..." : "Check Latest GitHub Release") {
                    checkForUpdate()
                }
                .disabled(isChecking)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let updateInfo {
                    Button("Open Release \(updateInfo.version)") {
                        openURL(updateInfo.releaseURL)
                    }
                }
            } header: {
                Text("Manual Updates")
            }
        }
        .formStyle(.grouped)
    }

    private func checkForUpdate() {
        isChecking = true
        updateInfo = nil
        statusMessage = nil

        UpdateChecker.checkForUpdate { result in
            isChecking = false

            switch result {
            case .updateAvailable(let info):
                updateInfo = info
                statusMessage = "Version \(info.version) is available on GitHub Releases."
            case .upToDate:
                statusMessage = "You already have the latest release."
            case .error(let error):
                statusMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    UpdatesSettingsPane()
        .frame(width: 450, height: 300)
}
