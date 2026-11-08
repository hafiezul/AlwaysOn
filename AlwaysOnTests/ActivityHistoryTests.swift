import XCTest
@testable import AlwaysOnTests

final class ActivityLedgerTests: XCTestCase {
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    func testOnlineStretchBecomesOneSegment() {
        var ledger = ActivityLedger()
        XCTAssertTrue(ledger.update(isOnline: true, kind: .manual, now: date(9, 9)))
        XCTAssertFalse(ledger.update(isOnline: true, kind: .manual, now: date(9, 10)), "same state is a no-op")
        XCTAssertTrue(ledger.update(isOnline: false, kind: .manual, now: date(9, 11)))
        XCTAssertEqual(ledger.segments, [ActivitySegment(start: date(9, 9), end: date(9, 11), kind: .manual)])
        XCTAssertFalse(ledger.isRecording)
    }

    func testKindChangeSplitsTheSegment() {
        var ledger = ActivityLedger()
        ledger.update(isOnline: true, kind: .schedule, now: date(9, 9))
        ledger.update(isOnline: true, kind: .timer, now: date(9, 12))
        ledger.update(isOnline: false, kind: .timer, now: date(9, 13))
        XCTAssertEqual(ledger.segments.map(\.kind), [.schedule, .timer])
        XCTAssertEqual(ledger.segments.map(\.duration), [3 * 3600, 3600] as [TimeInterval])
    }

    func testSubSecondFlipsAreNotRecorded() {
        var ledger = ActivityLedger()
        ledger.update(isOnline: true, kind: .manual, now: date(9, 9))
        ledger.update(isOnline: false, kind: .manual, now: date(9, 9).addingTimeInterval(0.2))
        XCTAssertTrue(ledger.segments.isEmpty)
    }

    func testTodayCountsTheOpenSegmentUpToNow() {
        var ledger = ActivityLedger()
        ledger.update(isOnline: true, kind: .manual, now: date(9, 8))
        ledger.update(isOnline: false, kind: .manual, now: date(9, 9))
        ledger.update(isOnline: true, kind: .manual, now: date(9, 10))
        XCTAssertEqual(ledger.today(now: date(9, 10, 30)), 3600 + 1800)
    }

    func testSegmentAcrossMidnightIsSplitBetweenDays() {
        var ledger = ActivityLedger()
        ledger.update(isOnline: true, kind: .until, now: date(9, 23))
        ledger.update(isOnline: false, kind: .until, now: date(10, 2))
        let days = ledger.daily(days: 2, now: date(10, 12))
        XCTAssertEqual(days.map(\.day), [date(9, 0), date(10, 0)])
        XCTAssertEqual(days.map(\.total), [3600, 2 * 3600] as [TimeInterval])
        XCTAssertEqual(days[1].byKind, [.until: TimeInterval(2 * 3600)])
    }

    func testDailyReturnsEveryDayOldestFirstIncludingEmptyOnes() {
        var ledger = ActivityLedger()
        ledger.update(isOnline: true, kind: .manual, now: date(5, 9))
        ledger.update(isOnline: false, kind: .manual, now: date(5, 10))
        let week = ledger.daily(days: 7, now: date(9, 12))
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.first?.day, date(3, 0))
        XCTAssertEqual(week.last?.day, date(9, 0))
        XCTAssertEqual(week.map(\.total), [0, 0, 3600, 0, 0, 0, 0] as [TimeInterval])
    }

    func testRelaunchClosesOpenSegmentAtLastCheckpoint() {
        var ledger = ActivityLedger()
        ledger.update(isOnline: true, kind: .manual, now: date(9, 9))
        ledger.checkpoint(at: date(9, 9, 40))
        ledger.recoverAfterRelaunch()
        XCTAssertEqual(ledger.segments, [ActivitySegment(start: date(9, 9), end: date(9, 9, 40), kind: .manual)])
        XCTAssertFalse(ledger.isRecording)
    }

    func testPruneDropsDaysOutsideRetention() {
        var ledger = ActivityLedger()
        ledger.update(isOnline: true, kind: .manual, now: date(1, 9))
        ledger.update(isOnline: false, kind: .manual, now: date(1, 10))
        ledger.update(isOnline: true, kind: .manual, now: date(20, 9))
        ledger.update(isOnline: false, kind: .manual, now: date(20, 10))
        var later = ledger
        later.prune(now: Calendar.current.date(byAdding: .day, value: ActivityLedger.retentionDays, to: date(10, 12))!)
        XCTAssertEqual(later.segments.map(\.start), [date(20, 9)])
    }

    func testSessionKindFollowsSource() {
        XCTAssertEqual(SessionKind(nil), .manual)
        XCTAssertEqual(SessionKind(.workSchedule(profileName: "Work")), .schedule)
        XCTAssertEqual(SessionKind(.quickTimer), .timer)
        XCTAssertEqual(SessionKind(.until(date: Date(), label: nil)), .until)
        XCTAssertEqual(SessionKind(.command(token: UUID(), deadline: Date())), .command)
        XCTAssertEqual(SessionKind(.focus), .focus)
    }

    func testDurationFormat() {
        XCTAssertEqual(ActivityDurationFormat.long(0), "0m")
        XCTAssertEqual(ActivityDurationFormat.long(20), "<1m")
        XCTAssertEqual(ActivityDurationFormat.long(45 * 60), "45m")
        XCTAssertEqual(ActivityDurationFormat.long(3 * 3600), "3h")
        XCTAssertEqual(ActivityDurationFormat.long(3 * 3600 + 12 * 60 + 59), "3h 12m")
    }
}

final class ActivityHistoryStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL { directory.appendingPathComponent("history.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testHistorySurvivesRelaunch() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let store = ActivityHistoryStore(fileURL: fileURL, now: start)
        store.update(isOnline: true, kind: .schedule, now: start)
        store.update(isOnline: false, kind: .schedule, now: start.addingTimeInterval(600))

        let reopened = ActivityHistoryStore(fileURL: fileURL, now: start.addingTimeInterval(700))
        XCTAssertEqual(reopened.ledger.segments,
                       [ActivitySegment(start: start, end: start.addingTimeInterval(600), kind: .schedule)])
    }

    func testCrashKeepsTimeUpToTheLastCheckpoint() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let store = ActivityHistoryStore(fileURL: fileURL, now: start)
        store.update(isOnline: true, kind: .manual, now: start)
        // Within the interval nothing is written; past it, the checkpoint lands
        store.checkpoint(now: start.addingTimeInterval(60))
        store.checkpoint(now: start.addingTimeInterval(ActivityHistoryStore.checkpointInterval + 1))

        let reopened = ActivityHistoryStore(fileURL: fileURL, now: start.addingTimeInterval(3600))
        XCTAssertEqual(reopened.ledger.segments.first?.duration, ActivityHistoryStore.checkpointInterval + 1)
        XCTAssertFalse(reopened.ledger.isRecording)
    }

    func testClearKeepsARunningSegmentGoingFromNow() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let store = ActivityHistoryStore(fileURL: nil, now: start)
        store.update(isOnline: true, kind: .timer, now: start)
        store.clear(now: start.addingTimeInterval(100))
        XCTAssertTrue(store.ledger.segments.isEmpty)
        XCTAssertEqual(store.ledger.open?.start, start.addingTimeInterval(100))
        XCTAssertEqual(store.ledger.open?.kind, .timer)
    }

    func testUnreadableFileStartsEmpty() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)
        XCTAssertTrue(ActivityHistoryStore(fileURL: fileURL).ledger.segments.isEmpty)
    }
}

final class SafetyStopsTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testOwnInputIsNotMistakenForTheUser() {
        var tracker = RealInputTracker(start: start)
        // We post at t=45; at t=90 the latest input is our return event at 45.05
        tracker.recordSyntheticPost(at: start.addingTimeInterval(45))
        tracker.observe(idleSeconds: 44.95, now: start.addingTimeInterval(90))
        XCTAssertEqual(tracker.lastRealInput, start)
        XCTAssertEqual(tracker.awayDuration(now: start.addingTimeInterval(90)), 90)
    }

    func testUserInputBetweenTicksIsRecorded() {
        var tracker = RealInputTracker(start: start)
        tracker.recordSyntheticPost(at: start.addingTimeInterval(45))
        // The user typed at t=70; at t=90 idle is 20 seconds
        tracker.observe(idleSeconds: 20, now: start.addingTimeInterval(90))
        XCTAssertEqual(tracker.lastRealInput, start.addingTimeInterval(70))
    }

    func testLatestRealInputNeverMovesBackwards() {
        var tracker = RealInputTracker(start: start)
        tracker.observe(idleSeconds: 5, now: start.addingTimeInterval(100))
        tracker.observe(idleSeconds: 500, now: start.addingTimeInterval(200))
        XCTAssertEqual(tracker.lastRealInput, start.addingTimeInterval(95))
    }

    func testInvalidIdleIsIgnored() {
        var tracker = RealInputTracker(start: start)
        tracker.observe(idleSeconds: .nan, now: start.addingTimeInterval(10))
        tracker.observe(idleSeconds: -1, now: start.addingTimeInterval(10))
        XCTAssertEqual(tracker.lastRealInput, start)
    }

    func testAwayLimit() {
        XCTAssertFalse(AwayLimit.off.isReached(awayFor: 1_000_000))
        XCTAssertFalse(AwayLimit.twoHours.isReached(awayFor: 2 * 3600 - 1))
        XCTAssertTrue(AwayLimit.twoHours.isReached(awayFor: 2 * 3600))
    }

    func testBatteryThreshold() {
        let low = BatteryState(isOnBattery: true, percent: 20)
        XCTAssertTrue(BatteryStopThreshold.twenty.shouldStop(low))
        XCTAssertFalse(BatteryStopThreshold.ten.shouldStop(low))
        XCTAssertFalse(BatteryStopThreshold.off.shouldStop(low))
        XCTAssertFalse(BatteryStopThreshold.fifty.shouldStop(BatteryState(isOnBattery: false, percent: 5)), "plugged in")
        XCTAssertFalse(BatteryStopThreshold.fifty.shouldStop(.noBattery))
    }

    func testBatteryPercent() {
        XCTAssertEqual(BatteryState.percent(current: 42, maximum: 100), 42)
        XCTAssertEqual(BatteryState.percent(current: 1500, maximum: 3000), 50)
        XCTAssertEqual(BatteryState.percent(current: 42, maximum: nil), 42)
        XCTAssertNil(BatteryState.percent(current: nil, maximum: 100))
    }

    func testStopMessagesNameTheReason() {
        let away = AutoStopEvent(reason: .awayLimit(.fourHours), date: start)
        XCTAssertTrue(away.message.contains("4 hours"))
        let battery = AutoStopEvent(reason: .lowBattery(percent: 18), date: start)
        XCTAssertTrue(battery.message.contains("18%"))
    }
}
