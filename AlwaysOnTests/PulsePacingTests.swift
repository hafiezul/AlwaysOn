import XCTest
@testable import AlwaysOnTests

final class PulseScheduleTests: XCTestCase {
    private let adaptive = PulseSchedule(pacing: .adaptive, interval: 45, postAfter: 120)

    // MARK: Fixed pacing

    func testFixedPacingAlwaysPostsOnItsInterval() {
        let fixed = PulseSchedule(pacing: .fixed, interval: 45)
        XCTAssertTrue(fixed.isDue(idleSeconds: 0))
        XCTAssertEqual(fixed.nextDelay(idleSeconds: 0), 45)
        XCTAssertEqual(fixed.nextDelay(idleSeconds: 500), 45)
    }

    func testEnergySavingDoublesTheIntervalUpToTwoMinutes() {
        func stretched(_ interval: TimeInterval) -> TimeInterval {
            PulseSchedule(pacing: .fixed, interval: interval, savesEnergy: true).effectiveInterval
        }
        XCTAssertEqual(stretched(30), 60)
        XCTAssertEqual(stretched(45), 90)
        XCTAssertEqual(stretched(60), 120)
        XCTAssertEqual(stretched(90), 120, "capped at two minutes")
        XCTAssertEqual(stretched(300), 300, "a longer chosen interval is never shortened")
    }

    func testIntervalIsUnchangedWithoutEnergySaving() {
        XCTAssertEqual(PulseSchedule(pacing: .fixed, interval: 45).effectiveInterval, 45)
    }

    // MARK: Adaptive pacing

    func testAdaptiveWaitsUntilIdleReachesThreshold() {
        XCTAssertFalse(adaptive.isDue(idleSeconds: 10))
        XCTAssertEqual(adaptive.nextDelay(idleSeconds: 10), 110)
        XCTAssertEqual(adaptive.nextDelay(idleSeconds: 100), 20)
    }

    func testAdaptivePostsAtThresholdAndWaitsAFullPeriodAfter() {
        XCTAssertTrue(adaptive.isDue(idleSeconds: 120))
        XCTAssertTrue(adaptive.isDue(idleSeconds: 119), "within the slack counts as due")
        XCTAssertEqual(adaptive.nextDelay(idleSeconds: 120), 120)
    }

    func testAdaptiveHeldBackByAnotherRuleDoesNotSpin() {
        // Idle far past the threshold (no target app): check again a full period later
        XCTAssertEqual(adaptive.nextDelay(idleSeconds: 900), 120)
    }

    func testAdaptiveNeverSchedulesFasterThanMinimum() {
        XCTAssertEqual(adaptive.nextDelay(idleSeconds: 118.5), 120, "inside the slack counts as due")
        XCTAssertEqual(adaptive.nextDelay(idleSeconds: 117.5), PulseSchedule.minimumDelay,
                       "just outside the slack waits the minimum, not 2.5 s")
    }

    func testAdaptiveTreatsInvalidIdleAsAFullPeriod() {
        XCTAssertEqual(adaptive.nextDelay(idleSeconds: -1), 120)
        XCTAssertEqual(adaptive.nextDelay(idleSeconds: .infinity), 120)
    }

    func testAdaptiveWakesFarLessThanFixedWhileUserWorks() {
        // A user typing continuously keeps idle near zero
        let wakesPerHourAdaptive = 3600 / adaptive.nextDelay(idleSeconds: 1)
        let wakesPerHourFixed = 3600 / PulseSchedule(pacing: .fixed, interval: 45).nextDelay(idleSeconds: 1)
        XCTAssertLessThan(wakesPerHourAdaptive * 2, wakesPerHourFixed)
    }

    // MARK: Screen saver and tolerance

    func testPostAfterStaysBeforeTheScreenSaver() {
        XCTAssertEqual(PulseSchedule.postAfter(chosen: .fourMinutes, screenSaverDelay: nil), 240)
        XCTAssertEqual(PulseSchedule.postAfter(chosen: .fourMinutes, screenSaverDelay: 0), 240)
        XCTAssertEqual(PulseSchedule.postAfter(chosen: .fourMinutes, screenSaverDelay: 1200), 240)
        XCTAssertEqual(PulseSchedule.postAfter(chosen: .fourMinutes, screenSaverDelay: 180), 165)
        XCTAssertEqual(PulseSchedule.postAfter(chosen: .twoMinutes, screenSaverDelay: 60), 45)
        XCTAssertEqual(PulseSchedule.postAfter(chosen: .twoMinutes, screenSaverDelay: 20),
                       PulseSchedule.shortestPostAfter)
    }

    func testToleranceGrowsWhileSavingEnergy() {
        let normal = PulseSchedule(pacing: .fixed, interval: 45)
        let saving = PulseSchedule(pacing: .fixed, interval: 45, savesEnergy: true)
        XCTAssertEqual(normal.tolerance(for: 45), 4.5, accuracy: 0.001)
        XCTAssertEqual(normal.tolerance(for: 120), 5)
        XCTAssertEqual(saving.tolerance(for: 45), 9, accuracy: 0.001)
        XCTAssertEqual(saving.tolerance(for: 120), 10)
    }

    func testEnergyStateSummary() {
        XCTAssertNil(EnergyState().summary)
        XCTAssertFalse(EnergyState().isConstrained)
        XCTAssertTrue(EnergyState(isLowPowerMode: true).isConstrained)
        XCTAssertTrue(EnergyState(isThermallyConstrained: true).isConstrained)
        XCTAssertNotNil(EnergyState(isLowPowerMode: true, isThermallyConstrained: true).summary)
    }
}

final class SleepPreventionPolicyTests: XCTestCase {
    private func level(_ setting: SleepPrevention, _ pacing: PulsePacing = .fixed, active: Bool = true,
                       suspension: SystemConditions.SuspensionReason? = nil,
                       targetReady: Bool = true) -> PowerAssertionLevel? {
        SleepPreventionPolicy.requiredLevel(setting: setting, pacing: pacing, isActive: active,
                                            suspension: suspension, targetAppReady: targetReady)
    }

    func testNothingHeldWithoutAnActiveSession() {
        for setting in SleepPrevention.allCases {
            XCTAssertNil(level(setting, .adaptive, active: false))
        }
    }

    func testSettingChoosesTheAssertion() {
        XCTAssertNil(level(.off))
        XCTAssertEqual(level(.system), .system)
        XCTAssertEqual(level(.systemAndDisplay), .display)
    }

    func testAdaptivePacingKeepsTheDisplayAwakeLikeFixedInputDid() {
        XCTAssertEqual(level(.off, .adaptive), .display)
        XCTAssertEqual(level(.system, .adaptive), .display)
    }

    func testAdaptiveLetsTheDisplaySleepWithNoTargetApp() {
        XCTAssertNil(level(.off, .adaptive, targetReady: false))
        XCTAssertEqual(level(.system, .adaptive, targetReady: false), .system)
        XCTAssertEqual(level(.systemAndDisplay, .adaptive, targetReady: false), .display)
    }

    func testLockedScreenKeepsOnlyTheMacAwake() {
        XCTAssertNil(level(.off, .adaptive, suspension: .screenLocked))
        XCTAssertEqual(level(.system, suspension: .screenLocked), .system)
        XCTAssertEqual(level(.systemAndDisplay, .adaptive, suspension: .screenLocked), .system)
    }

    func testSleepAndUserSwitchReleaseEverything() {
        XCTAssertNil(level(.systemAndDisplay, suspension: .asleep))
        XCTAssertNil(level(.systemAndDisplay, .adaptive, suspension: .sessionInactive))
    }
}
