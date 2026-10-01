import XCTest
@testable import AlwaysOnTests

final class QuickTimerDurationTests: XCTestCase {
    func testFromIdFallsBackToNoLimit() {
        XCTAssertEqual(QuickTimerDuration.from(id: "30m"), .minutes30)
        XCTAssertEqual(QuickTimerDuration.from(id: "8h"), .hours8)
        XCTAssertEqual(QuickTimerDuration.from(id: "unknown"), .noLimit)
        XCTAssertEqual(QuickTimerDuration.from(id: nil), .noLimit)
    }

    func testCustomDurationsRoundTripThroughId() {
        XCTAssertEqual(QuickTimerDuration.from(id: "custom:90"), .custom(minutes: 90))
        XCTAssertEqual(QuickTimerDuration.custom(minutes: 90).id, "custom:90")
        XCTAssertEqual(QuickTimerDuration.from(id: "custom:0"), .noLimit)
        XCTAssertEqual(QuickTimerDuration.from(id: "custom:9999"), .noLimit)
    }

    func testCustomDurationSeconds() {
        XCTAssertEqual(QuickTimerDuration.custom(minutes: 90).seconds, 5400)
        XCTAssertEqual(QuickTimerDuration.custom(minutes: 60).title, "1 hour")
        XCTAssertEqual(QuickTimerDuration.custom(minutes: 120).title, "2 hours")
        XCTAssertEqual(QuickTimerDuration.custom(minutes: 45).title, "45 minutes")
    }

    func testSecondsMatchTitles() {
        XCTAssertEqual(QuickTimerDuration.minutes30.seconds, 1800)
        XCTAssertEqual(QuickTimerDuration.hour1.seconds, 3600)
        XCTAssertEqual(QuickTimerDuration.hours8.seconds, 28800)
        XCTAssertNil(QuickTimerDuration.noLimit.seconds)
    }
}
