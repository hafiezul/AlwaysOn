import SwiftUI

/// Updates settings pane for manual update from GitHub Releases
struct UpdatesSettingsPane: View {
    @Environment(\.openURL) private var openURL
    @State private var isChecking = false
    @State private var updateInfo: UpdateChecker.UpdateInfo?
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section {
                Text("This build uses manual updates because it is not signed with Apple Developer ID.")
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

            Section {
                Text("Download updates from GitHub Releases. If Accessibility access breaks after installing a new version, remove the old AlwaysOn entry from Accessibility settings and re-add it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("About Updates")
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
