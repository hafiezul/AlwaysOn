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

    func switchProfile(to id: UUID) -> Profile? {
        guard id != activeProfileId else { return nil }
        guard let newProfile = profiles.first(where: { $0.id == id }) else { return nil }

        activeProfileId = id
        persist()

        return newProfile
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

    func updateProfileSettings(
        _ id: UUID,
        activityInterval: TimeInterval,
        activityMethod: ActivityMethod,
        defaultTimerDuration: QuickTimerDuration,
        workSchedule: WorkSchedule
    ) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }

        profiles[index].activityInterval = activityInterval
        profiles[index].activityMethodId = activityMethod.rawValue
        profiles[index].defaultTimerDurationId = defaultTimerDuration.id
        profiles[index].workSchedule = workSchedule
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

        defaults.set(encodeProfiles([defaultProfile]), forKey: Keys.profiles)
        defaults.set(defaultProfile.id.uuidString, forKey: Keys.activeProfileId)
        defaults.set(true, forKey: Keys.profilesMigrated)
    }

    private func persist() {
        defaults.set(Self.encodeProfiles(profiles), forKey: Keys.profiles)

        defaults.set(activeProfileId.uuidString, forKey: Keys.activeProfileId)
    }

    private static func encodeProfiles(_ profiles: [Profile]) -> Data {
        try! JSONEncoder().encode(profiles)
    }
}
