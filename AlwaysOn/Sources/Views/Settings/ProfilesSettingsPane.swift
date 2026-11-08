import SwiftUI

struct ProfilesSettingsPane: View {
    @EnvironmentObject var appState: AppState

    @State private var isShowingAddProfileSheet = false
    @State private var editingProfileId: UUID?
    @State private var draftName = ""
    @State private var newProfileName = ""
    @State private var pendingActivateProfileId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profiles")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Switch settings by context. Profile switches always stop the current session and clear any running timer.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    newProfileName = nextProfileName()
                    isShowingAddProfileSheet = true
                } label: {
                    Label("Add Profile", systemImage: "plus")
                }
            }

            List {
                ForEach(appState.profileManager.profiles) { profile in
                    profileRow(profile)
                }
            }
            .listStyle(.inset)

            wifiSwitching

            Text("Per-profile settings: activity interval, activity method, auto-disable timer, work hours schedule, and Wi-Fi networks. Onboarding, permissions, notifications, and launch at login stay global.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .sheet(isPresented: $isShowingAddProfileSheet) {
            addProfileSheet
        }
        .alert("Switch Profile?", isPresented: Binding(
            get: { pendingActivateProfileId != nil },
            set: { if !$0 { pendingActivateProfileId = nil } }
        )) {
            Button("Switch & Stop Session", role: .destructive) {
                if let id = pendingActivateProfileId { appState.switchProfile(id) }
                pendingActivateProfileId = nil
            }
            Button("Cancel", role: .cancel) { pendingActivateProfileId = nil }
        } message: {
            Text("Switching profiles will stop and clear the current session.")
        }
    }

    @ViewBuilder
    private func profileRow(_ profile: Profile) -> some View {
        let isActive = profile.id == appState.profileManager.activeProfileId
        let canDelete = appState.profileManager.profiles.count > 1

        HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isActive ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                if editingProfileId == profile.id {
                    TextField("Profile Name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            commitRename(for: profile)
                        }
                } else {
                    Text(profile.name)
                        .fontWeight(isActive ? .semibold : .regular)
                        .onTapGesture(count: 2) {
                            editingProfileId = profile.id
                            draftName = profile.name
                        }
                }

                Text(description(for: profile))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !profile.wifiNetworks.isEmpty {
                    Label(profile.wifiNetworks.joined(separator: ", "), systemImage: "wifi")
                        .font(.caption)
                        .foregroundColor(appState.switchProfilesByNetwork ? .secondary : .secondary.opacity(0.6))
                        .lineLimit(1)
                        .help(appState.switchProfilesByNetwork ? "Joining these networks switches to \(profile.name)"
                                                               : "Wi-Fi switching is off")
                }
            }

            Spacer()

            if isActive {
                Text("Active")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if appState.switchProfilesByNetwork {
                networkMenu(for: profile)
            }

            Button {
                editingProfileId = profile.id
                draftName = profile.name
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                deleteProfile(profile)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(!canDelete)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard editingProfileId != profile.id else { return }
            if appState.isActive || appState.activeSessionDuration > 0 {
                pendingActivateProfileId = profile.id
            } else {
                appState.switchProfile(profile.id)
            }
        }
        .contextMenu {
            Button("Activate") {
                if appState.isActive || appState.activeSessionDuration > 0 {
                    pendingActivateProfileId = profile.id
                } else {
                    appState.switchProfile(profile.id)
                }
            }
            .disabled(isActive)

            Button("Rename") {
                editingProfileId = profile.id
                draftName = profile.name
            }

            Button("Delete", role: .destructive) {
                deleteProfile(profile)
            }
            .disabled(!canDelete)
        }
    }

    // MARK: - Wi-Fi switching

    private var wifiSwitching: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Switch profiles by Wi-Fi network", isOn: $appState.switchProfilesByNetwork)

            if appState.switchProfilesByNetwork {
                if appState.wifiMonitor.locationAccess == .granted {
                    Label(appState.wifiMonitor.currentNetwork.map { "Connected to \u{201C}\($0)\u{201D}" } ?? "Not connected to Wi-Fi",
                          systemImage: appState.wifiMonitor.currentNetwork == nil ? "wifi.slash" : "wifi")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    PermissionRow(model: .location(appState), compact: true)
                }
                if let pending = appState.pendingNetworkProfileId,
                   let name = appState.profileManager.profiles.first(where: { $0.id == pending })?.name {
                    Label("Switches to \(name) when the current session ends", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Text("Use a profile's Wi-Fi button to add the network you're on. A running session always finishes before the profile changes, and a profile you pick by hand stays until you join another network.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private func networkMenu(for profile: Profile) -> some View {
        Menu {
            if let current = appState.wifiMonitor.currentNetwork {
                Button("Use on \u{201C}\(current)\u{201D}") { appState.useCurrentNetwork(for: profile.id) }
                    .disabled(profile.wifiNetworks.contains(current))
            } else {
                Text(appState.wifiMonitor.locationAccess == .granted ? "Not connected to Wi-Fi" : "Allow Location to see the network")
            }
            if !profile.wifiNetworks.isEmpty {
                Divider()
                ForEach(profile.wifiNetworks, id: \.self) { network in
                    Button("Remove \u{201C}\(network)\u{201D}") {
                        appState.profileManager.removeNetwork(network, from: profile.id)
                    }
                }
            }
        } label: {
            Image(systemName: profile.wifiNetworks.isEmpty ? "wifi" : "wifi.circle.fill")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Wi-Fi networks for \(profile.name)")
    }

    private var addProfileSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Profile")
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Name", text: $newProfileName)
                .textFieldStyle(.roundedBorder)

            Text("The new profile starts as a copy of the current profile's settings.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Spacer()

                Button("Cancel") {
                    isShowingAddProfileSheet = false
                }

                Button("Create") {
                    addProfile()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func addProfile() {
        let trimmedName = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let profile = Profile(
            id: UUID(),
            name: trimmedName,
            activityInterval: appState.activityInterval,
            activityMethodId: appState.activityMethod.rawValue,
            defaultTimerDurationId: appState.defaultTimerDuration.id,
            workSchedule: appState.workScheduleManager.schedule
        )

        appState.profileManager.addProfile(profile)
        newProfileName = ""
        isShowingAddProfileSheet = false
    }

    private func commitRename(for profile: Profile) {
        appState.profileManager.renameProfile(profile.id, to: draftName)
        editingProfileId = nil
        draftName = ""
    }

    private func deleteProfile(_ profile: Profile) {
        let wasActive = profile.id == appState.profileManager.activeProfileId
        appState.profileManager.deleteProfile(profile.id)

        if wasActive, let fallbackProfile = appState.profileManager.activeProfile {
            appState.stopSession()
            appState.applyProfile(fallbackProfile)
        }
    }

    private func description(for profile: Profile) -> String {
        let activityMethod = ActivityMethod(rawValue: profile.activityMethodId)?.title ?? ActivityMethod.mouse.title
        let timerTitle = QuickTimerDuration.from(id: profile.defaultTimerDurationId).title
        let scheduleText = profile.workSchedule.isEnabled ? profile.workSchedule.activeDaysDescription : "No work hours"
        return "\(formatInterval(profile.activityInterval)) | \(activityMethod) | \(timerTitle) | \(scheduleText)"
    }

    private func formatInterval(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 {
            return "Every \(seconds)s"
        }

        let minutes = seconds / 60
        return minutes == 1 ? "Every 1 min" : "Every \(minutes) min"
    }

    private func nextProfileName() -> String {
        let existingNames = Set(appState.profileManager.profiles.map(\.name))
        var index = 2
        var candidate = "Profile \(index)"

        while existingNames.contains(candidate) {
            index += 1
            candidate = "Profile \(index)"
        }

        return candidate
    }
}

#Preview {
    ProfilesSettingsPane()
        .environmentObject(AppState())
        .frame(width: 500, height: 420)
}
