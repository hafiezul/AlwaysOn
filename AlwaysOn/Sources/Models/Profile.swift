import Foundation

struct Profile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var activityInterval: TimeInterval
    var activityMethodId: String
    var defaultTimerDurationId: String
    var workSchedule: WorkSchedule

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
