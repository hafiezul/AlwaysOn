import XCTest
@testable import AlwaysOnTests

final class SystemConditionsTests: XCTestCase {
    func testNormalConditionsDoNotSuspend() {
        XCTAssertNil(SystemConditions().suspensionReason(pauseWhileLocked: true))
    }

    func testSleepAndUserSwitchAlwaysSuspend() {
        XCTAssertEqual(SystemConditions(isAsleep: true).suspensionReason(pauseWhileLocked: false), .asleep)
        XCTAssertEqual(SystemConditions(isSessionInactive: true).suspensionReason(pauseWhileLocked: false), .sessionInactive)
    }

    func testLockSuspendsOnlyWhenChosen() {
        let locked = SystemConditions(isScreenLocked: true)
        XCTAssertEqual(locked.suspensionReason(pauseWhileLocked: true), .screenLocked)
        XCTAssertNil(locked.suspensionReason(pauseWhileLocked: false))
    }

    func testSleepOutranksLock() {
        let both = SystemConditions(isAsleep: true, isScreenLocked: true)
        XCTAssertEqual(both.suspensionReason(pauseWhileLocked: true), .asleep)
    }
}

final class HeartbeatPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func delay(remaining: TimeInterval?, running: Bool = true, menu: Bool = false) -> TimeInterval? {
        HeartbeatPlanner.nextTickDelay(now: now, deadline: remaining.map { now.addingTimeInterval($0) },
                                       isRunning: running, isMenuVisible: menu)
    }

    /// The menu bar label exactly as AlwaysOnApp formats it
    private func label(_ remaining: TimeInterval) -> String {
        remaining < 60 ? "\(Int(remaining))s" : "\(Int((remaining / 60).rounded()))m"
    }

    func testUnlimitedSessionWithMenuClosedNeedsNoHeartbeat() {
        XCTAssertNil(delay(remaining: nil))
    }

    func testOpenMenuTicksEverySecond() {
        XCTAssertEqual(delay(remaining: nil, menu: true), 1)
        XCTAssertEqual(delay(remaining: 3600, menu: true), 1)
        XCTAssertEqual(delay(remaining: 3600, running: false, menu: true), 1)
    }

    func testPausedSessionWithoutDeadlineNeedsNoHeartbeatEvenWithMenuOpen() {
        XCTAssertNil(delay(remaining: nil, running: false, menu: true))
    }

    func testPausedSessionWakesOnlyAtDeadline() {
        XCTAssertEqual(delay(remaining: 3600, running: false), 3600)
    }

    func testExpiredDeadlineTicksImmediately() {
        XCTAssertEqual(delay(remaining: 0), 0)
        XCTAssertEqual(delay(remaining: -5, running: false), 0)
    }

    func testFinalMinuteTicksEverySecond() {
        XCTAssertEqual(delay(remaining: 60), 1)
        XCTAssertEqual(delay(remaining: 12), 1)
    }

    func testMinuteLabelWakesJustAfterRoundedValueChanges() {
        // 10m shown until 9.5 minutes remain
        XCTAssertEqual(delay(remaining: 600)!, 30 + HeartbeatPlanner.boundaryLead, accuracy: 0.001)
        // Between 60 and 90 seconds the next change is the switch to seconds
        XCTAssertEqual(delay(remaining: 89)!, 29 + HeartbeatPlanner.boundaryLead, accuracy: 0.001)
    }

    /// Walk a whole countdown tick by tick and check the label never shows a
    /// stale value for longer than the timer lead plus its tolerance
    func testWalkingACountdownNeverLeavesAStaleLabel() {
        var remaining: TimeInterval = 2 * 3600 + 17
        var ticks = 0
        while remaining > 0 {
            let step = delay(remaining: remaining)!
            XCTAssertGreaterThan(step, 0)
            let shownAtTick = label(remaining)
            // Just before the next tick the label must not have changed yet,
            // except within the small lead past a boundary
            let beforeNext = remaining - step + HeartbeatPlanner.boundaryLead + 0.001
            if beforeNext > 0 && step > 1 {
                XCTAssertEqual(label(beforeNext), shownAtTick, "label changed early at \(remaining)s remaining")
            }
            remaining -= step
            ticks += 1
        }
        // About one tick per minute plus sixty in the final minute, far below 7,217 per-second ticks
        XCTAssertLessThan(ticks, 200)
    }

    func testToleranceIsBounded() {
        XCTAssertEqual(HeartbeatPlanner.tolerance(for: 1), 0.1, accuracy: 0.0001)
        XCTAssertEqual(HeartbeatPlanner.tolerance(for: 30), 3, accuracy: 0.0001)
        XCTAssertEqual(HeartbeatPlanner.tolerance(for: 3600), 5)
    }
}

final class RunningAppMonitorTests: XCTestCase {
    private let center = NotificationCenter()
    private var running: [String] = []

    private func makeMonitor() -> RunningAppMonitor {
        RunningAppMonitor(notificationCenter: center,
                          runningBundleIDs: { [unowned self] in self.running },
                          bundleIDOf: { $0.userInfo?["id"] as? String })
    }

    private func post(_ name: Notification.Name, _ id: String) {
        center.post(name: name, object: nil, userInfo: ["id": id])
    }

    func testSeedsFromSnapshotAndFollowsLaunchAndQuit() {
        running = ["com.example.slack"]
        let monitor = makeMonitor()
        monitor.setEnabled(true)
        XCTAssertTrue(monitor.isAnyRunning(["com.example.slack"]))
        XCTAssertFalse(monitor.isAnyRunning(["com.example.teams"]))

        post(NSWorkspace.didLaunchApplicationNotification, "com.example.teams")
        XCTAssertTrue(monitor.isAnyRunning(["com.example.teams"]))

        post(NSWorkspace.didTerminateApplicationNotification, "com.example.teams")
        XCTAssertFalse(monitor.isAnyRunning(["com.example.teams"]))
    }

    func testCountsMultipleInstances() {
        let monitor = makeMonitor()
        monitor.setEnabled(true)
        post(NSWorkspace.didLaunchApplicationNotification, "com.example.zoom")
        post(NSWorkspace.didLaunchApplicationNotification, "com.example.zoom")
        post(NSWorkspace.didTerminateApplicationNotification, "com.example.zoom")
        XCTAssertTrue(monitor.isAnyRunning(["com.example.zoom"]))
        post(NSWorkspace.didTerminateApplicationNotification, "com.example.zoom")
        XCTAssertFalse(monitor.isAnyRunning(["com.example.zoom"]))
    }

    func testDisabledMonitorIgnoresNotificationsButStillAnswersFromSnapshot() {
        let monitor = makeMonitor()
        post(NSWorkspace.didLaunchApplicationNotification, "com.example.teams")
        XCTAssertFalse(monitor.isAnyRunning(["com.example.teams"]))
        running = ["com.example.teams"]
        XCTAssertTrue(monitor.isAnyRunning(["com.example.teams"]))
    }

    func testDisablingStopsObserving() {
        let monitor = makeMonitor()
        monitor.setEnabled(true)
        monitor.setEnabled(false)
        monitor.setEnabled(true)
        post(NSWorkspace.didLaunchApplicationNotification, "com.example.slack")
        // Exactly one observer pair: one launch means one count
        post(NSWorkspace.didTerminateApplicationNotification, "com.example.slack")
        XCTAssertFalse(monitor.isAnyRunning(["com.example.slack"]))
    }
}
