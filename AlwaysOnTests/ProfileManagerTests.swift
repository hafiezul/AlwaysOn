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
}

private final class RecordingDefaults: UserDefaults {
    var writes: [String] = []

    override func set(_ value: Any?, forKey defaultName: String) {
        writes.append(defaultName)
        super.set(value, forKey: defaultName)
    }
}
