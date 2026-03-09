import Foundation

@MainActor
final class ProfileManager: ObservableObject {
    @Published private(set) var profiles: [Profile]
    @Published private(set) var activeProfileId: UUID

    private let defaults: UserDefaults

    private enum Keys {
        static let profiles = "alwayson.profiles"
        static let activeProfileId = "alwayson.activeProfileId"
        static let profilesMigrated = "alwayson.profilesMigrated"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let loadedProfiles: [Profile]
        if let data = defaults.data(forKey: Keys.profiles),
           let decodedProfiles = try? JSONDecoder().decode([Profile].self, from: data),
           !decodedProfiles.isEmpty {
            loadedProfiles = decodedProfiles
        } else {
            loadedProfiles = [Profile.makeDefault(from: defaults)]
        }

        self.profiles = loadedProfiles

        if let activeProfileIdString = defaults.string(forKey: Keys.activeProfileId),
           let storedActiveProfileId = UUID(uuidString: activeProfileIdString),
           loadedProfiles.contains(where: { $0.id == storedActiveProfileId }) {
            self.activeProfileId = storedActiveProfileId
        } else {
            self.activeProfileId = loadedProfiles[0].id
        }

        persist()
    }

    var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileId }
    }

    func switchProfile(_ id: UUID, in appState: AppState) {
        guard id != activeProfileId else { return }
        guard let newProfile = profiles.first(where: { $0.id == id }) else { return }

        updateProfileSettings(activeProfileId, from: appState)
        let wasActive = appState.isActive || appState.activeSessionDuration > 0

        // Priority: Manual user action > Profile switch > Work Schedule
        appState.stopSession()

        activeProfileId = id
        persist()

        appState.applyProfile(newProfile)

        if wasActive {
            appState.notificationManager.notifyProfileSwitchedDuringSession(newProfileName: newProfile.name)
        }
    }

    func addProfile(_ profile: Profile) {
        profiles.append(profile)
        persist()
    }

    func deleteProfile(_ id: UUID) {
        guard profiles.count > 1 else { return }

        profiles.removeAll { $0.id == id }

        if !profiles.contains(where: { $0.id == activeProfileId }), let fallbackProfile = profiles.first {
            activeProfileId = fallbackProfile.id
        }

        persist()
    }

    func renameProfile(_ id: UUID, to name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        profiles[index].name = trimmedName
        persist()
    }

    func updateProfileSettings(_ id: UUID, from appState: AppState) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }

        profiles[index].activityInterval = appState.activityInterval
        profiles[index].activityMethodId = appState.activityMethod.rawValue
        profiles[index].defaultTimerDurationId = appState.defaultTimerDuration.id
        profiles[index].workSchedule = appState.workScheduleManager.schedule
        persist()
    }

    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: Keys.profilesMigrated) else { return }

        if let data = defaults.data(forKey: Keys.profiles),
           let decodedProfiles = try? JSONDecoder().decode([Profile].self, from: data),
           !decodedProfiles.isEmpty {
            defaults.set(true, forKey: Keys.profilesMigrated)
            return
        }

        let defaultProfile = Profile.makeDefault(from: defaults)

        if let profileData = try? JSONEncoder().encode([defaultProfile]) {
            defaults.set(profileData, forKey: Keys.profiles)
        }
        defaults.set(defaultProfile.id.uuidString, forKey: Keys.activeProfileId)
        defaults.set(true, forKey: Keys.profilesMigrated)
    }

    private func persist() {
        if let profileData = try? JSONEncoder().encode(profiles) {
            defaults.set(profileData, forKey: Keys.profiles)
        }

        defaults.set(activeProfileId.uuidString, forKey: Keys.activeProfileId)
    }
}
