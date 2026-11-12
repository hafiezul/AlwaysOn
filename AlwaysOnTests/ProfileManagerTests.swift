import XCTest
import Combine
@testable import AlwaysOnTests

@MainActor
final class ProfileManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AlwaysOnTests.profileManager.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSettingsUpdatesPublishAndPersistOnlyWhenChanged() {
        let recordingDefaults = RecordingDefaults(suiteName: suiteName)!
        let manager = ProfileManager(defaults: recordingDefaults)
        let original = manager.profiles[0]
        let other = Profile(id: UUID(), name: "Other", activityInterval: 60,
                            activityMethodId: ActivityMethod.keyboard.rawValue,
                            defaultTimerDurationId: QuickTimerDuration.hour1.id, workSchedule: .default)
        manager.addProfile(other)
        let activeId = manager.activeProfileId
        recordingDefaults.writes.removeAll()
        var publications: [[Profile]] = []
        let subscription = manager.$profiles.dropFirst().sink { publications.append($0) }

        manager.updateProfileSettings(original.id, activityInterval: original.activityInterval,
                                      activityMethod: original.activityMethod,
                                      defaultTimerDuration: original.defaultTimerDuration,
                                      workSchedule: original.workSchedule)
        XCTAssertTrue(publications.isEmpty)
        XCTAssertTrue(recordingDefaults.writes.isEmpty)

        var expected = original
        expected.activityInterval = 123
        expected.activityMethodId = ActivityMethod.keyboard.rawValue
        expected.defaultTimerDurationId = QuickTimerDuration.hour1.id
        var schedule = original.workSchedule
        schedule.isEnabled.toggle()
        expected.workSchedule = schedule
        manager.updateProfileSettings(original.id, activityInterval: 123, activityMethod: .keyboard,
                                      defaultTimerDuration: .hour1, workSchedule: schedule)

        XCTAssertEqual(publications, [[expected, other]])
        XCTAssertEqual(manager.profiles, [expected, other])
        XCTAssertEqual(ProfileManager.loadProfiles(from: recordingDefaults), [expected, other])
        XCTAssertEqual(manager.activeProfileId, activeId)
        XCTAssertEqual(recordingDefaults.string(forKey: "alwayson.activeProfileId"), activeId.uuidString)
        XCTAssertEqual(recordingDefaults.writes, ["alwayson.profiles", "alwayson.activeProfileId"])
        withExtendedLifetime(subscription) {}
    }

    func testSwitchOnlyPersistsActiveIdAndIgnoresInvalidSwitches() {
        let recordingDefaults = RecordingDefaults(suiteName: suiteName)!
        let manager = ProfileManager(defaults: recordingDefaults)
        let original = manager.profiles[0]
        let second = Profile(id: UUID(), name: "Second", activityInterval: 60,
                             activityMethodId: ActivityMethod.keyboard.rawValue,
                             defaultTimerDurationId: QuickTimerDuration.hour1.id, workSchedule: .default)
        manager.addProfile(second)
        let savedBytes = recordingDefaults.data(forKey: "alwayson.profiles")
        recordingDefaults.writes.removeAll()
        var publications: [UUID] = []
        let subscription = manager.$activeProfileId.dropFirst().sink { publications.append($0) }

        XCTAssertNil(manager.switchProfile(to: original.id))
        XCTAssertNil(manager.switchProfile(to: UUID()))
        XCTAssertTrue(publications.isEmpty)
        XCTAssertTrue(recordingDefaults.writes.isEmpty)

        XCTAssertEqual(manager.switchProfile(to: second.id), second)
        XCTAssertEqual(publications, [second.id])
        XCTAssertEqual(recordingDefaults.writes, ["alwayson.activeProfileId"])
        XCTAssertEqual(recordingDefaults.data(forKey: "alwayson.profiles"), savedBytes)
        XCTAssertEqual(manager.profiles, [original, second])
        XCTAssertEqual(ProfileManager(defaults: recordingDefaults).activeProfileId, second.id)
        withExtendedLifetime(subscription) {}
    }

    func testNoOpRenamesAndUnknownDeletionDoNotPublishOrPersist() {
        let recordingDefaults = RecordingDefaults(suiteName: suiteName)!
        let manager = ProfileManager(defaults: recordingDefaults)
        let original = manager.profiles[0]
        let second = Profile(id: UUID(), name: "Second", activityInterval: 60,
                             activityMethodId: ActivityMethod.keyboard.rawValue,
                             defaultTimerDurationId: QuickTimerDuration.hour1.id, workSchedule: .default)
        manager.addProfile(second)
        recordingDefaults.writes.removeAll()
        var publications: [[Profile]] = []
        let subscription = manager.$profiles.dropFirst().sink { publications.append($0) }

        manager.renameProfile(second.id, to: "Second")
        manager.renameProfile(second.id, to: "  Second  ")
        manager.deleteProfile(UUID())
        XCTAssertTrue(publications.isEmpty)
        XCTAssertTrue(recordingDefaults.writes.isEmpty)

        manager.renameProfile(second.id, to: "  Renamed  ")
        var renamed = second
        renamed.name = "Renamed"
        XCTAssertEqual(publications, [[original, renamed]])
        XCTAssertEqual(ProfileManager.loadProfiles(from: recordingDefaults), [original, renamed])
        XCTAssertEqual(recordingDefaults.writes, ["alwayson.profiles", "alwayson.activeProfileId"])
        withExtendedLifetime(subscription) {}
    }

    func testMigrationCreatesDefaultProfileFromLegacyKeys() {
        defaults.set(120.0, forKey: "activityInterval")
        defaults.set("keyboard", forKey: "activityMethod")

        ProfileManager.migrateIfNeeded(defaults: defaults)

        let profile = ProfileManager.loadProfiles(from: defaults)?.first
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.activityInterval, 120.0)
        XCTAssertEqual(profile?.activityMethod, .keyboard)
        XCTAssertTrue(defaults.bool(forKey: "alwayson.profilesMigrated"))
    }

    func testMigrationSkipsWhenProfilesAlreadyExist() {
        var profile = Profile.makeDefault(from: defaults)
        profile.name = "Existing"
        defaults.set(ProfileManager.encodeProfiles([profile]), forKey: "alwayson.profiles")

        ProfileManager.migrateIfNeeded(defaults: defaults)

        XCTAssertEqual(ProfileManager.loadProfiles(from: defaults)?.first?.name, "Existing")
    }

    func testSwitchProfilePersistsActiveId() {
        let profileManager = ProfileManager(defaults: defaults)
        let newProfile = Profile(
            id: UUID(),
            name: "Second",
            activityInterval: 60,
            activityMethodId: ActivityMethod.keyboard.rawValue,
            defaultTimerDurationId: QuickTimerDuration.hour1.id,
            workSchedule: .default
        )
        profileManager.addProfile(newProfile)

        let switched = profileManager.switchProfile(to: newProfile.id)

        XCTAssertEqual(switched?.name, "Second")
        XCTAssertEqual(profileManager.activeProfileId, newProfile.id)
        XCTAssertEqual(defaults.string(forKey: "alwayson.activeProfileId"), newProfile.id.uuidString)
    }

    func testDeleteProfileFallsBackToFirstRemaining() {
        let profileManager = ProfileManager(defaults: defaults)
        let secondProfile = Profile(
            id: UUID(),
            name: "Second",
            activityInterval: 60,
            activityMethodId: ActivityMethod.keyboard.rawValue,
            defaultTimerDurationId: QuickTimerDuration.hour1.id,
            workSchedule: .default
        )
        profileManager.addProfile(secondProfile)

        profileManager.deleteProfile(profileManager.activeProfileId)

        XCTAssertEqual(profileManager.activeProfileId, secondProfile.id)
        XCTAssertEqual(profileManager.profiles.count, 1)
        XCTAssertEqual(ProfileManager(defaults: defaults).activeProfileId, secondProfile.id)
    }

    func testDeleteLastProfileIsRefused() {
        let profileManager = ProfileManager(defaults: defaults)

        profileManager.deleteProfile(profileManager.activeProfileId)

        XCTAssertEqual(profileManager.profiles.count, 1)
    }

    // MARK: - Wi-Fi networks

    private func makeProfile(_ name: String, networks: [String] = []) -> Profile {
        Profile(id: UUID(), name: name, activityInterval: 45, activityMethodId: ActivityMethod.mouse.rawValue,
                defaultTimerDurationId: QuickTimerDuration.noLimit.id, workSchedule: .default, wifiNetworks: networks)
    }

    func testProfilesSavedBeforeWiFiSwitchingStillLoad() throws {
        let legacy = """
        [{"id":"\(UUID().uuidString)","name":"Old","activityInterval":45,"activityMethodId":"mouse",
          "defaultTimerDurationId":"none","workSchedule":{"isEnabled":false,"activeDays":[2],"startTimeMinutes":540,"endTimeMinutes":1020}}]
        """
        let profiles = try JSONDecoder().decode([Profile].self, from: Data(legacy.utf8))
        XCTAssertEqual(profiles.first?.name, "Old")
        XCTAssertEqual(profiles.first?.wifiNetworks, [])
    }

    func testWiFiNetworksRoundTrip() throws {
        let profile = makeProfile("Office", networks: ["Acme", "Acme Guest"])
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
    }

    func testRulePicksTheProfileListingTheNetwork() {
        let home = makeProfile("Home", networks: ["HomeNet"])
        let office = makeProfile("Office", networks: ["Acme"])
        XCTAssertEqual(NetworkProfileRule.profileID(forNetwork: "Acme", in: [home, office]), office.id)
        XCTAssertNil(NetworkProfileRule.profileID(forNetwork: "Cafe", in: [home, office]))
        XCTAssertNil(NetworkProfileRule.profileID(forNetwork: nil, in: [home, office]))
        XCTAssertNil(NetworkProfileRule.profileID(forNetwork: "", in: [home, office]))
    }

    func testAssigningANetworkMovesItFromAnyOtherProfile() {
        let manager = ProfileManager(defaults: defaults)
        let first = manager.profiles[0]
        let second = makeProfile("Office")
        manager.addProfile(second)

        manager.assignNetwork("Acme", to: first.id)
        manager.assignNetwork("  Acme ", to: second.id)

        XCTAssertEqual(manager.profiles.first { $0.id == first.id }?.wifiNetworks, [])
        XCTAssertEqual(manager.profiles.first { $0.id == second.id }?.wifiNetworks, ["Acme"])

        let reloaded = ProfileManager(defaults: defaults)
        XCTAssertEqual(reloaded.profiles.first { $0.id == second.id }?.wifiNetworks, ["Acme"])
    }

    func testRemovingANetwork() {
        let manager = ProfileManager(defaults: defaults)
        let id = manager.profiles[0].id
        manager.assignNetwork("Acme", to: id)
        manager.removeNetwork("Acme", from: id)
        XCTAssertEqual(manager.profiles[0].wifiNetworks, [])
    }

    // MARK: - Per-profile behavior

    private func makeBehavior(pacing: PulsePacing = .adaptive, targets: [String] = ["com.example.chat"]) -> ProfileBehavior {
        ProfileBehavior(pulsePacingId: pacing.rawValue, adaptivePostAfterSeconds: 240,
                        simulateOnlyWhenIdle: true, requireTargetApp: true, targetApps: targets,
                        sleepPreventionId: SleepPrevention.system.rawValue, awayLimitHours: 4, batteryStopPercent: 20)
    }

    func testProfilesSavedBeforeBehaviorStillLoadWithoutOne() throws {
        let legacy = """
        [{"id":"\(UUID().uuidString)","name":"Old","activityInterval":45,"activityMethodId":"mouse",
          "defaultTimerDurationId":"none","wifiNetworks":["Office"],
          "workSchedule":{"isEnabled":false,"activeDays":[2],"startTimeMinutes":540,"endTimeMinutes":1020}}]
        """
        let profiles = try JSONDecoder().decode([Profile].self, from: Data(legacy.utf8))
        XCTAssertEqual(profiles.first?.wifiNetworks, ["Office"])
        XCTAssertNil(profiles.first?.behavior)
    }

    func testBehaviorSurvivesEncoding() throws {
        var profile = makeProfile("Office")
        profile.behavior = makeBehavior()
        let decoded = try JSONDecoder().decode([Profile].self, from: ProfileManager.encodeProfiles([profile]))
        XCTAssertEqual(decoded, [profile])
        XCTAssertEqual(decoded[0].behavior?.pulsePacing, .adaptive)
        XCTAssertEqual(decoded[0].behavior?.adaptivePostAfter, .fourMinutes)
        XCTAssertEqual(decoded[0].behavior?.sleepPrevention, .system)
        XCTAssertEqual(decoded[0].behavior?.awayLimit, .fourHours)
        XCTAssertEqual(decoded[0].behavior?.batteryStopThreshold, .twenty)
    }

    func testUnknownRawValuesFallBackToDefaults() {
        let behavior = ProfileBehavior(pulsePacingId: "warp", adaptivePostAfterSeconds: 7,
                                       simulateOnlyWhenIdle: false, requireTargetApp: false, targetApps: [],
                                       sleepPreventionId: "forever", awayLimitHours: 3, batteryStopPercent: 99)
        XCTAssertEqual(behavior.pulsePacing, .fixed)
        XCTAssertEqual(behavior.adaptivePostAfter, .twoMinutes)
        XCTAssertEqual(behavior.sleepPrevention, .off)
        XCTAssertEqual(behavior.awayLimit, .off)
        XCTAssertEqual(behavior.batteryStopThreshold, .off)
    }

    func testLegacyDefaultsWithNothingSavedMatchTheAppDefaults() {
        XCTAssertEqual(ProfileBehavior(legacyDefaults: defaults),
                       ProfileBehavior(pulsePacingId: "fixed", adaptivePostAfterSeconds: 120,
                                       simulateOnlyWhenIdle: false, requireTargetApp: false, targetApps: [],
                                       sleepPreventionId: "off", awayLimitHours: 0, batteryStopPercent: 0))
    }

    func testLegacyDefaultsReadTheGlobalKeys() {
        defaults.set("adaptive", forKey: "pulsePacing")
        defaults.set(60, forKey: "adaptivePostAfterSeconds")
        defaults.set(true, forKey: "simulateOnlyWhenIdle")
        defaults.set(true, forKey: "requireTargetApp")
        defaults.set(["us.zoom.xos", "com.example.chat"], forKey: "targetApps")
        defaults.set("systemAndDisplay", forKey: "sleepPrevention")
        defaults.set(8, forKey: "awayLimitHours")
        defaults.set(30, forKey: "batteryStopThreshold")

        XCTAssertEqual(ProfileBehavior(legacyDefaults: defaults),
                       ProfileBehavior(pulsePacingId: "adaptive", adaptivePostAfterSeconds: 60,
                                       simulateOnlyWhenIdle: true, requireTargetApp: true,
                                       targetApps: ["com.example.chat", "us.zoom.xos"],
                                       sleepPreventionId: "systemAndDisplay", awayLimitHours: 8, batteryStopPercent: 30))
    }

    func testBehaviorMigrationFillsOnlyProfilesWithoutOne() {
        defaults.set("adaptive", forKey: "pulsePacing")
        var kept = makeProfile("Kept")
        kept.behavior = makeBehavior(pacing: .fixed)
        let old = makeProfile("Old", networks: ["Office"])
        defaults.set(ProfileManager.encodeProfiles([old, kept]), forKey: "alwayson.profiles")

        ProfileManager.migrateBehaviorIfNeeded(defaults: defaults)

        let loaded = ProfileManager.loadProfiles(from: defaults)
        XCTAssertEqual(loaded?.map(\.name), ["Old", "Kept"])
        XCTAssertEqual(loaded?[0].behavior, ProfileBehavior(legacyDefaults: defaults))
        XCTAssertEqual(loaded?[0].behavior?.pulsePacing, .adaptive)
        XCTAssertEqual(loaded?[0].wifiNetworks, ["Office"])
        XCTAssertEqual(loaded?[1], kept)
    }

    func testBehaviorMigrationWritesNothingWhenNotNeeded() {
        let recordingDefaults = RecordingDefaults(suiteName: suiteName)!
        ProfileManager.migrateBehaviorIfNeeded(defaults: recordingDefaults)
        XCTAssertTrue(recordingDefaults.writes.isEmpty)

        var profile = makeProfile("Done")
        profile.behavior = makeBehavior()
        recordingDefaults.set(ProfileManager.encodeProfiles([profile]), forKey: "alwayson.profiles")
        recordingDefaults.writes.removeAll()
        ProfileManager.migrateBehaviorIfNeeded(defaults: recordingDefaults)
        XCTAssertTrue(recordingDefaults.writes.isEmpty)
    }

    func testNewInstallDefaultProfileHasBehavior() {
        XCTAssertEqual(Profile.makeDefault(from: defaults).behavior, ProfileBehavior(legacyDefaults: defaults))
    }

    func testUpdatingSettingsSavesBehaviorAndNilLeavesIt() {
        let manager = ProfileManager(defaults: defaults)
        let profile = manager.profiles[0]
        let behavior = makeBehavior()

        manager.updateProfileSettings(profile.id, activityInterval: profile.activityInterval,
                                      activityMethod: profile.activityMethod,
                                      defaultTimerDuration: profile.defaultTimerDuration,
                                      workSchedule: profile.workSchedule, behavior: behavior)
        XCTAssertEqual(manager.profiles[0].behavior, behavior)
        XCTAssertEqual(ProfileManager.loadProfiles(from: defaults)?.first?.behavior, behavior)

        manager.updateProfileSettings(profile.id, activityInterval: profile.activityInterval,
                                      activityMethod: profile.activityMethod,
                                      defaultTimerDuration: profile.defaultTimerDuration,
                                      workSchedule: profile.workSchedule)
        XCTAssertEqual(manager.profiles[0].behavior, behavior)
    }

    func testDuplicateCopiesSettingsButNotNetworks() {
        let manager = ProfileManager(defaults: defaults)
        var office = makeProfile("Office", networks: ["Office Wi-Fi"])
        office.behavior = makeBehavior()
        manager.addProfile(office)

        let copy = manager.duplicateProfile(office.id)
        XCTAssertEqual(copy?.name, "Office Copy")
        XCTAssertNotEqual(copy?.id, office.id)
        XCTAssertEqual(copy?.behavior, office.behavior)
        XCTAssertEqual(copy?.wifiNetworks, [])
        XCTAssertEqual(manager.duplicateProfile(office.id)?.name, "Office Copy 2")
        XCTAssertNil(manager.duplicateProfile(UUID()))
        XCTAssertEqual(ProfileManager.loadProfiles(from: defaults)?.count, 4)
        XCTAssertEqual(manager.profiles.first { $0.id == office.id }?.wifiNetworks, ["Office Wi-Fi"])
    }
}

private final class RecordingDefaults: UserDefaults {
    var writes: [String] = []

    override func set(_ value: Any?, forKey defaultName: String) {
        writes.append(defaultName)
        super.set(value, forKey: defaultName)
    }
}
