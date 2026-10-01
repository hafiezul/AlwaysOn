import XCTest

final class ActivityGateTests: XCTestCase {
    func testGateOffAlwaysPosts() {
        let gate = ActivityGate(idleOnlyEnabled: false)
        XCTAssertTrue(gate.shouldPost(idleSeconds: 0, hasRunningTarget: true))
        XCTAssertTrue(gate.shouldPost(idleSeconds: 300, hasRunningTarget: true))
    }

    func testIdleGateSkipsWhenUserRecentlyActive() {
        let gate = ActivityGate(idleOnlyEnabled: true)
        XCTAssertFalse(gate.shouldPost(idleSeconds: 0, hasRunningTarget: true))
        XCTAssertFalse(gate.shouldPost(idleSeconds: ActivityGate.idleThreshold - 1, hasRunningTarget: true))
    }

    func testIdleGatePostsOnceIdleReachesThreshold() {
        let gate = ActivityGate(idleOnlyEnabled: true)
        XCTAssertTrue(gate.shouldPost(idleSeconds: ActivityGate.idleThreshold, hasRunningTarget: true))
        XCTAssertTrue(gate.shouldPost(idleSeconds: 300, hasRunningTarget: true))
    }

    func testTargetGateSkipsWhenNoTargetRuns() {
        let gate = ActivityGate(requireTargetApp: true, targetBundleIDs: ["com.example.app"])
        XCTAssertFalse(gate.shouldPost(idleSeconds: 300, hasRunningTarget: false))
    }

    func testTargetGatePostsWhileTargetRuns() {
        let gate = ActivityGate(requireTargetApp: true, targetBundleIDs: ["com.example.app"])
        XCTAssertTrue(gate.shouldPost(idleSeconds: 300, hasRunningTarget: true))
    }

    func testBothGatesMustPass() {
        let gate = ActivityGate(idleOnlyEnabled: true, requireTargetApp: true, targetBundleIDs: ["com.example.app"])
        XCTAssertFalse(gate.shouldPost(idleSeconds: 5, hasRunningTarget: true))
        XCTAssertFalse(gate.shouldPost(idleSeconds: 300, hasRunningTarget: false))
        XCTAssertTrue(gate.shouldPost(idleSeconds: 300, hasRunningTarget: true))
    }
}
