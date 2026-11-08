import XCTest
@testable import AlwaysOnTests

final class WorkScheduleTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    func testDisabledScheduleIsNeverWithinSchedule() {
        let schedule = WorkSchedule(isEnabled: false)

        XCTAssertFalse(schedule.isWithinSchedule(on: date(2026, 3, 9, 12, 0)))
    }

    func testWindowIsInclusiveAtStartAndExclusiveAtEnd() {
        let schedule = WorkSchedule(
            isEnabled: true,
            activeDays: [2, 3, 4, 5, 6],
            startTimeMinutes: 9 * 60,
            endTimeMinutes: 17 * 60
        )

        XCTAssertTrue(schedule.isWithinSchedule(on: date(2026, 3, 9, 9, 0)))
        XCTAssertTrue(schedule.isWithinSchedule(on: date(2026, 3, 9, 16, 59)))
        XCTAssertFalse(schedule.isWithinSchedule(on: date(2026, 3, 9, 17, 0)))
        XCTAssertFalse(schedule.isWithinSchedule(on: date(2026, 3, 9, 8, 59)))
    }

    func testInactiveDaysAreExcluded() {
        let weekdaySchedule = WorkSchedule(
            isEnabled: true,
            activeDays: [2, 3, 4, 5, 6],
            startTimeMinutes: 9 * 60,
            endTimeMinutes: 17 * 60
        )

        let saturday = date(2026, 3, 14, 12, 0)
        let sunday = date(2026, 3, 15, 12, 0)

        XCTAssertFalse(weekdaySchedule.isWithinSchedule(on: saturday))
        XCTAssertFalse(weekdaySchedule.isWithinSchedule(on: sunday))
    }

    func testInitializationClampsToValidTimeRange() {
        let collapsed = WorkSchedule(startTimeMinutes: 600, endTimeMinutes: 600)
        XCTAssertEqual(collapsed.startTimeMinutes, 600)
        XCTAssertEqual(collapsed.endTimeMinutes, 601)

        let inverted = WorkSchedule(startTimeMinutes: 900, endTimeMinutes: 300)
        XCTAssertEqual(inverted.startTimeMinutes, 900)
        XCTAssertEqual(inverted.endTimeMinutes, 901)

        let overflown = WorkSchedule(startTimeMinutes: 2000, endTimeMinutes: 3000)
        XCTAssertEqual(overflown.startTimeMinutes, 1438)
        XCTAssertEqual(overflown.endTimeMinutes, 1439)
    }

    func testCodableRoundTripPreservesSchedule() throws {
        let schedule = WorkSchedule(
            isEnabled: true,
            activeDays: [1, 3, 7],
            startTimeMinutes: 570,
            endTimeMinutes: 1080
        )

        let data = try JSONEncoder().encode(schedule)
        let decoded = try JSONDecoder().decode(WorkSchedule.self, from: data)

        XCTAssertEqual(decoded, schedule)
    }

    func testActiveDaysDescriptionMatchesCommonPatterns() {
        var schedule = WorkSchedule.default
        schedule.activeDays = [2, 3, 4, 5, 6]
        XCTAssertEqual(schedule.activeDaysDescription, "Weekdays")

        schedule.activeDays = [1, 7]
        XCTAssertEqual(schedule.activeDaysDescription, "Weekends")

        schedule.activeDays = []
        XCTAssertEqual(schedule.activeDaysDescription, "No days selected")
    }

    // MARK: - Next transition

    private var weekdayNineToFive: WorkSchedule {
        WorkSchedule(isEnabled: true, activeDays: [2, 3, 4, 5, 6], startTimeMinutes: 9 * 60, endTimeMinutes: 17 * 60)
    }

    func testNextTransitionBeforeStartIsTodaysStart() {
        // 2026-03-09 is a Monday
        XCTAssertEqual(weekdayNineToFive.nextTransition(after: date(2026, 3, 9, 7, 30)), date(2026, 3, 9, 9, 0))
    }

    func testNextTransitionDuringHoursIsTodaysEnd() {
        XCTAssertEqual(weekdayNineToFive.nextTransition(after: date(2026, 3, 9, 9, 0)), date(2026, 3, 9, 17, 0))
        XCTAssertEqual(weekdayNineToFive.nextTransition(after: date(2026, 3, 9, 16, 59)), date(2026, 3, 9, 17, 0))
    }

    func testNextTransitionAfterHoursSkipsToNextActiveDay() {
        XCTAssertEqual(weekdayNineToFive.nextTransition(after: date(2026, 3, 9, 17, 0)), date(2026, 3, 10, 9, 0))
        // Friday evening skips the weekend
        XCTAssertEqual(weekdayNineToFive.nextTransition(after: date(2026, 3, 13, 18, 0)), date(2026, 3, 16, 9, 0))
    }

    func testNextTransitionAgreesWithWithinScheduleAcrossAWeek() {
        let schedule = weekdayNineToFive
        var moment = date(2026, 3, 8, 0, 0)
        let end = date(2026, 3, 15, 0, 0)
        while moment < end {
            guard let transition = schedule.nextTransition(after: moment) else { return XCTFail("no transition") }
            XCTAssertGreaterThan(transition, moment)
            // State holds until the transition and flips exactly at it
            XCTAssertEqual(schedule.isWithinSchedule(on: transition.addingTimeInterval(-1)), schedule.isWithinSchedule(on: moment))
            XCTAssertNotEqual(schedule.isWithinSchedule(on: transition), schedule.isWithinSchedule(on: moment))
            moment = transition
        }
    }

    func testNextTransitionIsNilWhenScheduleNeverChanges() {
        XCTAssertNil(WorkSchedule(isEnabled: false).nextTransition(after: date(2026, 3, 9, 12, 0)))
        XCTAssertNil(WorkSchedule(isEnabled: true, activeDays: []).nextTransition(after: date(2026, 3, 9, 12, 0)))
    }

    // MARK: - Menu hint

    func testMenuHintDuringHoursNamesTheEnd() {
        let hint = weekdayNineToFive.menuHint(now: date(2026, 3, 9, 10, 0))
        XCTAssertEqual(hint, "Work hours until \(date(2026, 3, 9, 17, 0).formatted(date: .omitted, time: .shortened))")
    }

    func testMenuHintNamesTodayTomorrowOrWeekday() {
        let nine = { (day: Int) in self.date(2026, 3, day, 9, 0).formatted(date: .omitted, time: .shortened) }
        XCTAssertEqual(weekdayNineToFive.menuHint(now: date(2026, 3, 9, 7, 0)), "Work hours start today at \(nine(9))")
        XCTAssertEqual(weekdayNineToFive.menuHint(now: date(2026, 3, 9, 18, 0)), "Work hours start tomorrow at \(nine(10))")
        let monday = date(2026, 3, 16, 9, 0).formatted(.dateTime.weekday(.wide))
        XCTAssertEqual(weekdayNineToFive.menuHint(now: date(2026, 3, 13, 18, 0)), "Work hours start \(monday) at \(nine(16))")
    }

    func testMenuHintIsNilWhenDisabled() {
        XCTAssertNil(WorkSchedule(isEnabled: false).menuHint(now: date(2026, 3, 9, 10, 0)))
    }

    // MARK: - Custom hours, breaks, and days off

    func testCustomHoursReplaceDefaultForThatDay() {
        var schedule = weekdayNineToFive
        // Friday 9:00-13:00
        schedule.setHours(MinuteRange(startMinutes: 9 * 60, endMinutes: 13 * 60), forWeekday: 6)
        XCTAssertTrue(schedule.isWithinSchedule(on: date(2026, 3, 13, 12, 59)))
        XCTAssertFalse(schedule.isWithinSchedule(on: date(2026, 3, 13, 13, 0)))
        XCTAssertTrue(schedule.isWithinSchedule(on: date(2026, 3, 12, 16, 0)), "Thursday keeps the default")
        XCTAssertEqual(schedule.nextTransition(after: date(2026, 3, 13, 10, 0)), date(2026, 3, 13, 13, 0))

        schedule.setHours(nil, forWeekday: 6)
        XCTAssertTrue(schedule.isWithinSchedule(on: date(2026, 3, 13, 16, 0)))
        XCTAssertFalse(schedule.hasCustomHours(forWeekday: 6))
    }

    func testSetHoursValidatesTheRange() {
        var schedule = weekdayNineToFive
        schedule.setHours(MinuteRange(startMinutes: 900, endMinutes: 300), forWeekday: 2)
        XCTAssertEqual(schedule.hours(forWeekday: 2), MinuteRange(startMinutes: 900, endMinutes: 901))
    }

    func testBreakSplitsTheDay() {
        var schedule = weekdayNineToFive
        schedule.breakTime = MinuteRange(startMinutes: 12 * 60, endMinutes: 13 * 60)
        let monday = date(2026, 3, 9, 0, 0)
        XCTAssertEqual(schedule.windows(on: monday), [MinuteRange(startMinutes: 540, endMinutes: 720),
                                                      MinuteRange(startMinutes: 780, endMinutes: 1020)])
        XCTAssertTrue(schedule.isWithinSchedule(on: date(2026, 3, 9, 11, 59)))
        XCTAssertFalse(schedule.isWithinSchedule(on: date(2026, 3, 9, 12, 30)))
        XCTAssertTrue(schedule.isWithinSchedule(on: date(2026, 3, 9, 13, 0)))
        XCTAssertEqual(schedule.nextTransition(after: date(2026, 3, 9, 10, 0)), date(2026, 3, 9, 12, 0))
        XCTAssertEqual(schedule.nextTransition(after: date(2026, 3, 9, 12, 0)), date(2026, 3, 9, 13, 0))
        XCTAssertEqual(schedule.workdayEnd(on: monday), date(2026, 3, 9, 17, 0))
    }

    func testBreakOutsideHoursChangesNothing() {
        var schedule = weekdayNineToFive
        schedule.breakTime = MinuteRange(startMinutes: 18 * 60, endMinutes: 19 * 60)
        XCTAssertEqual(schedule.windows(on: date(2026, 3, 9, 0, 0)), [MinuteRange(startMinutes: 540, endMinutes: 1020)])
    }

    func testBreakAtTheStartTrimsTheDay() {
        var schedule = weekdayNineToFive
        schedule.breakTime = MinuteRange(startMinutes: 8 * 60, endMinutes: 10 * 60)
        XCTAssertEqual(schedule.windows(on: date(2026, 3, 9, 0, 0)), [MinuteRange(startMinutes: 600, endMinutes: 1020)])
    }

    func testSkippedDayHasNoHoursAndTransitionsSkipIt() {
        var schedule = weekdayNineToFive
        schedule.setSkipped(true, on: date(2026, 3, 10, 15, 0))
        XCTAssertTrue(schedule.isSkipped(date(2026, 3, 10, 0, 0)))
        XCTAssertFalse(schedule.isWithinSchedule(on: date(2026, 3, 10, 12, 0)))
        XCTAssertEqual(schedule.nextTransition(after: date(2026, 3, 9, 18, 0)), date(2026, 3, 11, 9, 0))

        schedule.setSkipped(false, on: date(2026, 3, 10, 8, 0))
        XCTAssertTrue(schedule.isWithinSchedule(on: date(2026, 3, 10, 12, 0)))
    }

    func testTransitionsReachPastALongHoliday() {
        var schedule = weekdayNineToFive
        var day = date(2026, 3, 9, 12, 0)
        for _ in 0..<21 {
            schedule.setSkipped(true, on: day)
            day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        }
        // Three weeks off from Monday 9 March; back on Monday 30 March
        XCTAssertEqual(schedule.nextTransition(after: date(2026, 3, 9, 8, 0)), date(2026, 3, 30, 9, 0))
    }

    func testPruneDropsOnlyPastDays() {
        var schedule = weekdayNineToFive
        schedule.setSkipped(true, on: date(2026, 3, 2, 12, 0))
        schedule.setSkipped(true, on: date(2026, 3, 9, 12, 0))
        schedule.setSkipped(true, on: date(2026, 3, 20, 12, 0))
        schedule.pruneSkippedDays(before: date(2026, 3, 9, 18, 0))
        XCTAssertEqual(schedule.skippedDays, ["2026-03-09", "2026-03-20"])
    }

    func testMenuHintMentionsSkippedTodayAndBreaks() {
        var schedule = weekdayNineToFive
        schedule.setSkipped(true, on: date(2026, 3, 9, 0, 0))
        let nine = date(2026, 3, 10, 9, 0).formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(schedule.menuHint(now: date(2026, 3, 9, 10, 0)), "Skipping today · Work hours start tomorrow at \(nine)")

        var withBreak = weekdayNineToFive
        withBreak.breakTime = MinuteRange(startMinutes: 12 * 60, endMinutes: 13 * 60)
        let noon = date(2026, 3, 9, 12, 0).formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(withBreak.menuHint(now: date(2026, 3, 9, 10, 0)), "Work hours until \(noon), then a break")
        let five = date(2026, 3, 9, 17, 0).formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(withBreak.menuHint(now: date(2026, 3, 9, 14, 0)), "Work hours until \(five)")
    }

    func testNewFieldsRoundTripAndOldSchedulesStillDecode() throws {
        var schedule = weekdayNineToFive
        schedule.setHours(MinuteRange(startMinutes: 600, endMinutes: 900), forWeekday: 6)
        schedule.breakTime = MinuteRange(startMinutes: 720, endMinutes: 780)
        schedule.setSkipped(true, on: date(2026, 12, 25, 12, 0))
        let decoded = try JSONDecoder().decode(WorkSchedule.self, from: JSONEncoder().encode(schedule))
        XCTAssertEqual(decoded, schedule)

        let legacy = #"{"isEnabled":true,"activeDays":[2,3],"startTimeMinutes":540,"endTimeMinutes":1020}"#
        let old = try JSONDecoder().decode(WorkSchedule.self, from: Data(legacy.utf8))
        XCTAssertEqual(old.customHours, [])
        XCTAssertNil(old.breakTime)
        XCTAssertEqual(old.skippedDays, [])
        XCTAssertEqual(old.activeDays, [2, 3])
    }

    func testTimeUntilHelpersFollowWindows() {
        var schedule = weekdayNineToFive
        schedule.breakTime = MinuteRange(startMinutes: 12 * 60, endMinutes: 13 * 60)
        XCTAssertEqual(schedule.timeUntilEnd(now: date(2026, 3, 9, 11, 0)), 3600)
        XCTAssertEqual(schedule.timeUntilNextStart(now: date(2026, 3, 9, 12, 30)), 1800)
        XCTAssertNil(schedule.timeUntilNextStart(now: date(2026, 3, 9, 11, 0)))
    }
}
