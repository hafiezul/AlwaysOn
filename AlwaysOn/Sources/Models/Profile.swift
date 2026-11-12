import Foundation

struct Profile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var activityInterval: TimeInterval
    var activityMethodId: String
    var defaultTimerDurationId: String
    var workSchedule: WorkSchedule
    /// Wi-Fi network names (SSIDs) that switch to this profile when joined
    var wifiNetworks: [String] = []
    /// Pacing, target apps, sleep prevention, and safety stops. Nil only for
    /// a profile saved before these were per-profile, until migration fills it.
    var behavior: ProfileBehavior? = nil

    var activityMethod: ActivityMethod {
        ActivityMethod(rawValue: activityMethodId) ?? .mouse
    }

    var defaultTimerDuration: QuickTimerDuration {
        QuickTimerDuration.from(id: defaultTimerDurationId)
    }

    static func makeDefault(from defaults: UserDefaults = .standard) -> Profile {
        let activityInterval = defaults.double(forKey: "activityInterval")
        let interval = activityInterval > 0 ? activityInterval : 45.0

        let activityMethodId = defaults.string(forKey: "activityMethod") ?? ActivityMethod.mouse.rawValue
        let defaultTimerDurationId = defaults.string(forKey: "defaultTimerDuration") ?? QuickTimerDuration.noLimit.id

        let workSchedule: WorkSchedule
        if let data = defaults.data(forKey: "workSchedule"),
           let savedSchedule = try? JSONDecoder().decode(WorkSchedule.self, from: data) {
            workSchedule = savedSchedule
        } else {
            workSchedule = .default
        }

        return Profile(
            id: UUID(),
            name: "Default",
            activityInterval: interval,
            activityMethodId: activityMethodId,
            defaultTimerDurationId: defaultTimerDurationId,
            workSchedule: workSchedule,
            behavior: ProfileBehavior(legacyDefaults: defaults)
        )
    }
}

extension Profile {
    private enum CodingKeys: String, CodingKey {
        case id, name, activityInterval, activityMethodId, defaultTimerDurationId, workSchedule, wifiNetworks, behavior
    }

    /// Profiles saved by older versions have no network list and no behavior
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        activityInterval = try container.decode(TimeInterval.self, forKey: .activityInterval)
        activityMethodId = try container.decode(String.self, forKey: .activityMethodId)
        defaultTimerDurationId = try container.decode(String.self, forKey: .defaultTimerDurationId)
        workSchedule = try container.decode(WorkSchedule.self, forKey: .workSchedule)
        wifiNetworks = try container.decodeIfPresent([String].self, forKey: .wifiNetworks) ?? []
        behavior = try container.decodeIfPresent(ProfileBehavior.self, forKey: .behavior)
    }
}

/// The settings that differ by place, saved with each profile. Stored as
/// raw values, like the rest of Profile, so an unknown value falls back to
/// its default instead of failing to decode.
struct ProfileBehavior: Codable, Equatable {
    var pulsePacingId: String
    var adaptivePostAfterSeconds: Int
    var simulateOnlyWhenIdle: Bool
    var requireTargetApp: Bool
    /// Selected target app bundle IDs, sorted so equal selections compare equal
    var targetApps: [String]
    var sleepPreventionId: String
    var awayLimitHours: Int
    var batteryStopPercent: Int

    var pulsePacing: PulsePacing { PulsePacing(rawValue: pulsePacingId) ?? .fixed }
    var adaptivePostAfter: AdaptivePostAfter { AdaptivePostAfter(rawValue: adaptivePostAfterSeconds) ?? .twoMinutes }
    var sleepPrevention: SleepPrevention { SleepPrevention(rawValue: sleepPreventionId) ?? .off }
    var awayLimit: AwayLimit { AwayLimit(rawValue: awayLimitHours) ?? .off }
    var batteryStopThreshold: BatteryStopThreshold { BatteryStopThreshold(rawValue: batteryStopPercent) ?? .off }
}

extension ProfileBehavior {
    /// The values in use before these settings were per-profile, read from
    /// the keys AppState has always saved them under
    init(legacyDefaults defaults: UserDefaults) {
        self.init(
            pulsePacingId: (PulsePacing(rawValue: defaults.string(forKey: "pulsePacing") ?? "") ?? .fixed).rawValue,
            adaptivePostAfterSeconds: (AdaptivePostAfter(rawValue: defaults.integer(forKey: "adaptivePostAfterSeconds")) ?? .twoMinutes).rawValue,
            simulateOnlyWhenIdle: defaults.bool(forKey: "simulateOnlyWhenIdle"),
            requireTargetApp: defaults.bool(forKey: "requireTargetApp"),
            targetApps: (defaults.stringArray(forKey: "targetApps") ?? []).sorted(),
            sleepPreventionId: (SleepPrevention(rawValue: defaults.string(forKey: "sleepPrevention") ?? "") ?? .off).rawValue,
            awayLimitHours: (AwayLimit(rawValue: defaults.integer(forKey: "awayLimitHours")) ?? .off).rawValue,
            batteryStopPercent: (BatteryStopThreshold(rawValue: defaults.integer(forKey: "batteryStopThreshold")) ?? .off).rawValue
        )
    }
}

/// Picks the profile for the Wi-Fi network the Mac is on
enum NetworkProfileRule {
    /// The profile that lists `network`, or nil when none does or there is no network.
    /// ProfileManager keeps each network on at most one profile; if data ever
    /// disagrees, the first profile in list order wins.
    static func profileID(forNetwork network: String?, in profiles: [Profile]) -> UUID? {
        guard let network, !network.isEmpty else { return nil }
        return profiles.first { $0.wifiNetworks.contains(network) }?.id
    }
}

/// An automatic profile switch caused by joining a Wi-Fi network
struct NetworkSwitchEvent: Equatable {
    var profileName: String
    var network: String
    var date: Date

    var summary: String { "Switched to \(profileName) on \u{201C}\(network)\u{201D}" }
}
