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
    func testEvaluationCountsForEveryFlagCombination() {
        for idleEnabled in [false, true] {
            for targetEnabled in [false, true] {
                var idleCalls = 0
                var targetCalls = 0
                func idle() -> TimeInterval { idleCalls += 1; return ActivityGate.idleThreshold }
                func target() -> Bool { targetCalls += 1; return true }
                let gate = ActivityGate(idleOnlyEnabled: idleEnabled, requireTargetApp: targetEnabled)

                XCTAssertTrue(gate.shouldPost(idleSeconds: idle(), hasRunningTarget: target()))
                XCTAssertEqual(idleCalls, idleEnabled ? 1 : 0)
                XCTAssertEqual(targetCalls, targetEnabled ? 1 : 0)
            }
        }
    }

    func testIdleRejectionSkipsTargetProvider() {
        var idleCalls = 0
        var targetCalls = 0
        func idle() -> TimeInterval { idleCalls += 1; return ActivityGate.idleThreshold - 1 }
        func target() -> Bool { targetCalls += 1; return true }
        let gate = ActivityGate(idleOnlyEnabled: true, requireTargetApp: true)

        XCTAssertFalse(gate.shouldPost(idleSeconds: idle(), hasRunningTarget: target()))
        XCTAssertEqual(idleCalls, 1)
        XCTAssertEqual(targetCalls, 0)
    }

    func testTruthTableAtThresholdBoundary() {
        for idleEnabled in [false, true] {
            for targetEnabled in [false, true] {
                for idle in [ActivityGate.idleThreshold - 1, ActivityGate.idleThreshold] {
                    for target in [false, true] {
                        let gate = ActivityGate(idleOnlyEnabled: idleEnabled, requireTargetApp: targetEnabled)
                        let expected = (!idleEnabled || idle >= ActivityGate.idleThreshold) && (!targetEnabled || target)
                        XCTAssertEqual(gate.shouldPost(idleSeconds: idle, hasRunningTarget: target), expected)
                    }
                }
            }
        }
    }

}
