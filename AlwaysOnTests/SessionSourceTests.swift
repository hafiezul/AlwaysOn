import XCTest

final class SessionSourceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let token = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let other = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    func testUntilValidationAndExactExpiry() throws {
        let date = Date(timeIntervalSince1970: 1_100)
        let source = try XCTUnwrap(SessionSource.validatedUntil(date: date, label: "Planning", now: now, hasPermission: true))
        XCTAssertEqual(source, .until(date: date, label: "Planning"))
        let end = source.endCondition(quickTimerDeadline: nil)
        XCTAssertEqual(end.deadline, date)
        XCTAssertFalse(end.hasExpired(at: now))
        XCTAssertTrue(end.hasExpired(at: date))
        XCTAssertTrue(end.hasExpired(at: Date(timeIntervalSince1970: 1_101)))
        for invalid in [now, Date(timeIntervalSince1970: 999), Date(timeIntervalSinceReferenceDate: .infinity), Date(timeIntervalSinceReferenceDate: .nan)] {
            XCTAssertNil(SessionSource.validatedUntil(date: invalid, now: now, hasPermission: true))
        }
        XCTAssertNil(SessionSource.validatedUntil(date: date, now: now, hasPermission: false))
    }

    func testLatestCommandAndManualOwnership() {
        var source = SessionSource.runningCommand(token: token, now: now)
        XCTAssertTrue(source.endCondition(quickTimerDeadline: nil).matchesFinish(token: token))
        XCTAssertFalse(source.endCondition(quickTimerDeadline: nil).matchesFinish(token: other))
        source = .runningCommand(token: other, now: now)
        XCTAssertFalse(source.endCondition(quickTimerDeadline: nil).matchesFinish(token: token))
        XCTAssertTrue(source.endCondition(quickTimerDeadline: nil).matchesFinish(token: other))
        source = source.relinquishingCommand
        XCTAssertFalse(source.endCondition(quickTimerDeadline: nil).matchesFinish(token: other))
        XCTAssertEqual(source.endCondition(quickTimerDeadline: nil).deadline, Date(timeIntervalSince1970: 87_400))
        XCTAssertTrue(source.endCondition(quickTimerDeadline: nil).hasExpired(at: Date(timeIntervalSince1970: 87_400)))
        for replacement in [SessionSource.manual, .quickTimer, .workSchedule(profileName: "Work"), .until(date: now, label: nil)] {
            XCTAssertFalse(replacement.endCondition(quickTimerDeadline: nil).matchesFinish(token: token))
        }
    }

    func testRestoreRejectsExpiredSessionsAndOrphanCommands() throws {
        let future = Date(timeIntervalSince1970: 1_100)
        let source = SessionSource.until(date: future, label: "Meeting")
        let restored = try JSONDecoder().decode(SessionSource.self, from: JSONEncoder().encode(source))
        XCTAssertEqual(restored, source)
        XCTAssertTrue(restored.canRestore(quickTimerDeadline: nil, now: now))
        XCTAssertFalse(restored.canRestore(quickTimerDeadline: nil, now: future))
        XCTAssertTrue(SessionSource.quickTimer.canRestore(quickTimerDeadline: future, now: now))
        XCTAssertFalse(SessionSource.quickTimer.canRestore(quickTimerDeadline: now, now: now))
        XCTAssertFalse(SessionSource.runningCommand(token: token, now: now).canRestore(quickTimerDeadline: future, now: now))
        let legacy = Data(#"{"workSchedule":{"profileName":"Office"}}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(SessionSource.self, from: legacy), .workSchedule(profileName: "Office"))
    }

    func testPausedUntilRestoresOnlyBeforeItsOriginalDeadline() {
        let deadline = Date(timeIntervalSince1970: 1_100)
        let source = SessionSource.until(date: deadline, label: "Planning")
        XCTAssertTrue(source.canRestore(isActive: false, quickTimerDeadline: deadline, now: now))
        XCTAssertEqual(source.endCondition(quickTimerDeadline: deadline), .deadline(deadline))
        XCTAssertFalse(source.canRestore(isActive: false, quickTimerDeadline: deadline, now: deadline))
        XCTAssertFalse(SessionSource.runningCommand(token: token, now: now)
            .canRestore(isActive: false, quickTimerDeadline: deadline, now: now))
        XCTAssertFalse(SessionSource.manual.canRestore(isActive: false, quickTimerDeadline: nil, now: now))
    }
    func testAbsoluteDeadlineSurvivesPauseAndStaleTimerSnapshot() throws {
        let date = Date(timeIntervalSince1970: 1_100)
        let source = SessionSource.until(date: date, label: "Standup")
        // Pausing changes activity state, not the persisted source or its deadline.
        let paused = try JSONDecoder().decode(SessionSource.self, from: JSONEncoder().encode(source))
        let end = paused.endCondition(quickTimerDeadline: Date(timeIntervalSince1970: 9_000))
        XCTAssertEqual(end.deadline, date)
        XCTAssertFalse(end.hasExpired(at: Date(timeIntervalSince1970: 1_099)))
        XCTAssertTrue(end.hasExpired(at: Date(timeIntervalSince1970: 1_101)))
        XCTAssertEqual(paused.relinquishingCommand, source)
        let command = SessionSource.runningCommand(token: token, now: now)
        let restoredCommand = try JSONDecoder().decode(SessionSource.self, from: JSONEncoder().encode(command))
        XCTAssertEqual(restoredCommand, command)
        XCTAssertFalse(restoredCommand.canRestore(quickTimerDeadline: nil, now: now))
    }

    func testCancellingCountdownKeepsScheduleOwnershipButDropsChosenDeadline() {
        let date = Date(timeIntervalSince1970: 1_100)
        // A schedule-started session must still end with its schedule after the timer is cancelled.
        XCTAssertEqual(SessionSource.workSchedule(profileName: "Office").cancellingCountdown, .workSchedule(profileName: "Office"))
        XCTAssertEqual(SessionSource.quickTimer.cancellingCountdown, .quickTimer)
        XCTAssertEqual(SessionSource.manual.cancellingCountdown, .manual)
        for chosen in [SessionSource.until(date: date, label: "Review"), .command(token: token, deadline: date)] {
            XCTAssertEqual(chosen.chosenEndDate, date)
            let cancelled = chosen.cancellingCountdown
            XCTAssertEqual(cancelled, .manual)
            XCTAssertEqual(cancelled.endCondition(quickTimerDeadline: nil), .unlimited)
            XCTAssertFalse(cancelled.endCondition(quickTimerDeadline: nil).matchesFinish(token: token))
        }
        XCTAssertNil(SessionSource.quickTimer.chosenEndDate)
    }

    // MARK: - Adding time

    func testAddingTimeMovesAnExistingEndLater() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let end = now.addingTimeInterval(600)
        let change = SessionSource.quickTimer.addingTime(900, quickTimerDeadline: end, now: now)
        XCTAssertEqual(change.source, .quickTimer)
        XCTAssertEqual(change.deadline, end.addingTimeInterval(900))
    }

    func testAddingTimeToAnUnlimitedSessionGivesItAnEnd() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let change = SessionSource.manual.addingTime(3600, quickTimerDeadline: nil, now: now)
        XCTAssertEqual(change.source, .manual)
        XCTAssertEqual(change.deadline, now.addingTimeInterval(3600))
    }

    func testAddingTimeKeepsTheUntilLabelAndCountsFromNowWhenPast() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let source = SessionSource.until(date: now.addingTimeInterval(-60), label: "Standup")
        let change = source.addingTime(1800, quickTimerDeadline: nil, now: now)
        XCTAssertEqual(change.source, .until(date: now.addingTimeInterval(1800), label: "Standup"))
    }

    func testAddingTimeTakesOverACommandSession() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let deadline = now.addingTimeInterval(3600)
        let change = SessionSource.command(token: UUID(), deadline: deadline).addingTime(600, quickTimerDeadline: nil, now: now)
        XCTAssertEqual(change.source, .until(date: deadline.addingTimeInterval(600), label: nil))
        XCTAssertFalse(change.source.endCondition(quickTimerDeadline: nil).matchesFinish(token: UUID()))
    }

    func testFocusSessionsBehaveLikeManualButNeverRestore() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        XCTAssertEqual(SessionSource.focus.endCondition(quickTimerDeadline: nil), .unlimited)
        XCTAssertNil(SessionSource.focus.chosenEndDate)
        XCTAssertFalse(SessionSource.focus.canRestore(isActive: true, quickTimerDeadline: nil, now: now))
        XCTAssertEqual(SessionSource.focus.cancellingCountdown, .focus)
        let added = SessionSource.focus.addingTime(600, quickTimerDeadline: nil, now: now)
        XCTAssertEqual(added.source, .focus, "the Focus still owns a session given an end")
        XCTAssertEqual(added.deadline, now.addingTimeInterval(600))

        let decoded = try JSONDecoder().decode(SessionSource.self, from: JSONEncoder().encode(SessionSource.focus))
        XCTAssertEqual(decoded, .focus)
    }
}
