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
            workSchedule: workSchedule
        )
    }
}

extension Profile {
    private enum CodingKeys: String, CodingKey {
        case id, name, activityInterval, activityMethodId, defaultTimerDurationId, workSchedule, wifiNetworks
    }

    /// Profiles saved before Wi-Fi switching existed have no network list
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        activityInterval = try container.decode(TimeInterval.self, forKey: .activityInterval)
        activityMethodId = try container.decode(String.self, forKey: .activityMethodId)
        defaultTimerDurationId = try container.decode(String.self, forKey: .defaultTimerDurationId)
        workSchedule = try container.decode(WorkSchedule.self, forKey: .workSchedule)
        wifiNetworks = try container.decodeIfPresent([String].self, forKey: .wifiNetworks) ?? []
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
