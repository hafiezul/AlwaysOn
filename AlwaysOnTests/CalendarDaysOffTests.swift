import XCTest
@testable import AlwaysOnTests

final class CalendarDaysOffTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    /// Mon-Fri 9:00-17:00
    private var schedule: WorkSchedule {
        WorkSchedule(isEnabled: true, activeDays: [2, 3, 4, 5, 6], startTimeMinutes: 540, endTimeMinutes: 1020)
    }

    /// Monday 2026-03-09 08:00
    private var now: Date { date(2026, 3, 9, 8, 0) }

    private func block(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false,
                       _ availability: CalendarBlock.Availability) -> CalendarBlock {
        CalendarBlock(title: title, start: start, end: end, isAllDay: allDay, availability: availability)
    }

    func testOutOfOfficeCoveringWorkHoursIsSuggested() {
        let blocks = [block("Leave", date(2026, 3, 9, 0, 0), date(2026, 3, 10, 0, 0), .outOfOffice)]

        let result = CalendarDaysOff.suggestions(from: blocks, schedule: schedule, from: now)

        XCTAssertEqual(result.map(\.id), ["2026-03-09"])
        XCTAssertEqual(result.first?.isOutOfOffice, true)
        XCTAssertEqual(result.first?.reason, "Leave")
        XCTAssertEqual(result.first?.date, date(2026, 3, 9, 0, 0))
    }

    func testAllDayBusyEventIsSuggestedButNotMarkedOutOfOffice() {
        let blocks = [block("Conference", date(2026, 3, 10, 0, 0), date(2026, 3, 11, 0, 0), allDay: true, .busy)]

        let result = CalendarDaysOff.suggestions(from: blocks, schedule: schedule, from: now)

        XCTAssertEqual(result.map(\.id), ["2026-03-10"])
        XCTAssertEqual(result.first?.isOutOfOffice, false)
        XCTAssertEqual(result.first?.reason, "Conference")
    }

    func testAllDayFreeEventIsIgnored() {
        let blocks = [block("Birthday", date(2026, 3, 10, 0, 0), date(2026, 3, 11, 0, 0), allDay: true, .free)]

        XCTAssertEqual(CalendarDaysOff.suggestions(from: blocks, schedule: schedule, from: now), [])
    }

    func testPartialDayIsIgnored() {
        let blocks = [block("Afternoon off", date(2026, 3, 9, 13, 0), date(2026, 3, 9, 17, 0), .outOfOffice)]

        XCTAssertEqual(CalendarDaysOff.suggestions(from: blocks, schedule: schedule, from: now), [])
    }

    func testWeekendAndSkippedDaysAreIgnored() {
        let weekend = [block("Trip", date(2026, 3, 14, 0, 0), date(2026, 3, 16, 0, 0), .outOfOffice)]
        XCTAssertEqual(CalendarDaysOff.suggestions(from: weekend, schedule: schedule, from: now), [])

        var skipping = schedule
        skipping.skippedDays = ["2026-03-11"]
        let wednesday = [block("Leave", date(2026, 3, 11, 0, 0), date(2026, 3, 12, 0, 0), .outOfOffice)]
        XCTAssertEqual(CalendarDaysOff.suggestions(from: wednesday, schedule: skipping, from: now), [])
    }

    func testMultiDayLeaveGivesOneSuggestionPerWorkday() {
        let blocks = [block("Holiday", date(2026, 3, 13, 0, 0), date(2026, 3, 17, 0, 0), .outOfOffice)]

        let result = CalendarDaysOff.suggestions(from: blocks, schedule: schedule, from: now)

        XCTAssertEqual(result.map(\.id), ["2026-03-13", "2026-03-16"])
        XCTAssertEqual(result.map(\.isOutOfOffice), [true, true])
    }

    func testOutOfOfficeWinsWhenBothCover() {
        let blocks = [
            block("Conference", date(2026, 3, 12, 0, 0), date(2026, 3, 13, 0, 0), allDay: true, .busy),
            block("Leave", date(2026, 3, 12, 0, 0), date(2026, 3, 13, 0, 0), .outOfOffice)
        ]

        let result = CalendarDaysOff.suggestions(from: blocks, schedule: schedule, from: now)

        XCTAssertEqual(result.map(\.id), ["2026-03-12"])
        XCTAssertEqual(result.first?.reason, "Leave")
        XCTAssertEqual(result.first?.isOutOfOffice, true)
    }

    func testLookAheadIsBounded() {
        // 2026-05-18 is a Monday, 70 days after 2026-03-09
        let blocks = [block("Leave", date(2026, 5, 18, 0, 0), date(2026, 5, 19, 0, 0), .outOfOffice)]

        XCTAssertEqual(CalendarDaysOff.suggestions(from: blocks, schedule: schedule, from: now), [])
        XCTAssertEqual(CalendarDaysOff.suggestions(from: blocks, schedule: schedule, from: now, days: 71).map(\.id),
                       ["2026-05-18"])
    }

    func testBreakDoesNotHideAFullDay() {
        var withBreak = schedule
        withBreak.breakTime = MinuteRange(startMinutes: 720, endMinutes: 780)
        let blocks = [block("Leave", date(2026, 3, 9, 0, 0), date(2026, 3, 10, 0, 0), .outOfOffice)]

        let result = CalendarDaysOff.suggestions(from: blocks, schedule: withBreak, from: now)

        XCTAssertEqual(result.map(\.id), ["2026-03-09"])
        XCTAssertEqual(result.first?.isOutOfOffice, true)
    }
}
