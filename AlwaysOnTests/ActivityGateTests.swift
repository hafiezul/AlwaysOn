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

    func testSkipReasonsAndPulseHistory() {
        let gate = ActivityGate(idleOnlyEnabled: true, requireTargetApp: true)
        XCTAssertEqual(gate.decision(idleSeconds: 0, hasRunningTarget: false), .skip(.userActive))
        XCTAssertEqual(gate.decision(idleSeconds: 60, hasRunningTarget: false), .skip(.noTarget))
        XCTAssertEqual(gate.decision(idleSeconds: 60, hasRunningTarget: true), .post)
        let log = PulseLog()
        let date = Date(timeIntervalSince1970: 1_000)
        log.record(.userActive, date: date)
        XCTAssertEqual(log.history.first?.summary, "Skipped: user active")
        XCTAssertEqual(log.history.first?.date, date)
        let firstID = log.history.first?.id
        log.record(.noTarget, date: date)
        XCTAssertEqual(log.history.last?.summary, "Skipped: no target app")
        XCTAssertNotEqual(log.history.last?.id, firstID)
        log.record(.inputCreationFailed)
        XCTAssertEqual(log.history.last?.summary, "Input creation failed")
        for offset in 0..<201 { log.record(.posted, date: date.addingTimeInterval(Double(offset))) }
        XCTAssertEqual(log.history.count, 200)
        XCTAssertEqual(log.history.first?.date, Date(timeIntervalSince1970: 1_001))
        XCTAssertEqual(log.history.last?.date, Date(timeIntervalSince1970: 1_200))
        XCTAssertEqual(log.counts, [.userActive: 1, .noTarget: 1, .inputCreationFailed: 1, .posted: 201])
        XCTAssertEqual(log.latestOutcome, .posted)
        log.clear()
        XCTAssertEqual(log.history.count, 0)
        XCTAssertEqual(log.counts, [:])
        XCTAssertNil(log.latestOutcome)
        log.record(.noTarget)
        XCTAssertEqual(log.counts, [.noTarget: 1])
    }

    func testEveryOutcomeHasACategoryAndExplanation() {
        let all: [PulseLog.Outcome] = [.posted, .userActive, .noTarget, .inputCreationFailed,
                                       .systemPaused, .permissionMissing, .stoppedAway, .stoppedLowBattery]
        XCTAssertEqual(Set(all.map(\.category)), Set(PulseLog.Category.allCases))
        XCTAssertTrue(all.allSatisfy { !$0.explanation.isEmpty })
    }

    func testCategoryCountsAddUpOutcomes() {
        let log = PulseLog()
        [.posted, .posted, .userActive, .noTarget, .systemPaused, .inputCreationFailed, .stoppedAway]
            .forEach { log.record($0) }
        XCTAssertEqual(log.count(of: .posted), 2)
        XCTAssertEqual(log.count(of: .skipped), 2)
        XCTAssertEqual(log.count(of: .paused), 1)
        XCTAssertEqual(log.count(of: .problem), 2)
    }
}

final class SimulatedInputTests: XCTestCase {
    func testMethodsPickTheirInputWhenNothingPlays() {
        XCTAssertEqual(ActivityMethod.mouse.input(lastWasMouse: false, mediaPlaying: false), .mouse)
        XCTAssertEqual(ActivityMethod.keyboard.input(lastWasMouse: false, mediaPlaying: false), .keyboard)
        XCTAssertEqual(ActivityMethod.alternating.input(lastWasMouse: true, mediaPlaying: false), .keyboard)
        XCTAssertEqual(ActivityMethod.alternating.input(lastWasMouse: false, mediaPlaying: false), .mouse)
    }

    func testPlaybackAlwaysUsesKeyboard() {
        for method in ActivityMethod.allCases {
            for lastWasMouse in [false, true] {
                XCTAssertEqual(method.input(lastWasMouse: lastWasMouse, mediaPlaying: true), .keyboard)
            }
        }
    }
}
