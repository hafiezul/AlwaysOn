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
}
