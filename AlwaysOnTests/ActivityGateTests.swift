import XCTest

final class ActivityGateTests: XCTestCase {
    func testGateOffAlwaysPosts() {
        let gate = ActivityGate(idleOnlyEnabled: false)
        XCTAssertTrue(gate.shouldPost(idleSeconds: 0))
        XCTAssertTrue(gate.shouldPost(idleSeconds: 300))
    }

    func testGateOnSkipsWhenUserRecentlyActive() {
        let gate = ActivityGate(idleOnlyEnabled: true)
        XCTAssertFalse(gate.shouldPost(idleSeconds: 0))
        XCTAssertFalse(gate.shouldPost(idleSeconds: ActivityGate.idleThreshold - 1))
    }

    func testGateOnPostsOnceIdleReachesThreshold() {
        let gate = ActivityGate(idleOnlyEnabled: true)
        XCTAssertTrue(gate.shouldPost(idleSeconds: ActivityGate.idleThreshold))
        XCTAssertTrue(gate.shouldPost(idleSeconds: 300))
    }
}
