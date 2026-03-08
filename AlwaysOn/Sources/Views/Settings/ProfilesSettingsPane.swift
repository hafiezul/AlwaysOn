import SwiftUI

struct ProfilesSettingsPane: View {
    @EnvironmentObject var appState: AppState

    @State private var isShowingAddProfileSheet = false
    @State private var editingProfileId: UUID?
    @State private var draftName = ""
    @State private var newProfileName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profiles")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Switch settings by context. Profile switches always stop the current session and clear timer and smart-pause state.")
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

            Text("Per-profile settings: activity interval, activity method, auto-disable timer, and work hours schedule. Focus Mode, presentation detection, onboarding, permissions, and launch at login stay global.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .sheet(isPresented: $isShowingAddProfileSheet) {
            addProfileSheet
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
            }

            Spacer()

            if isActive {
                Text("Active")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
            appState.profileManager.switchProfile(profile.id, in: appState)
        }
        .contextMenu {
            Button("Activate") {
                appState.profileManager.switchProfile(profile.id, in: appState)
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
            appState.clearSmartPause()
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
