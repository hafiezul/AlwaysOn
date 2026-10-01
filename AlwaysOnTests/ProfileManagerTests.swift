import XCTest
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
    }

    func testDeleteLastProfileIsRefused() {
        let profileManager = ProfileManager(defaults: defaults)

        profileManager.deleteProfile(profileManager.activeProfileId)

        XCTAssertEqual(profileManager.profiles.count, 1)
    }
}
