import XCTest
@testable import AlwaysOnTests

final class QuickTimerDurationTests: XCTestCase {
    func testFromIdFallsBackToNoLimit() {
        XCTAssertEqual(QuickTimerDuration.from(id: "30m"), .minutes30)
        XCTAssertEqual(QuickTimerDuration.from(id: "8h"), .hours8)
        XCTAssertEqual(QuickTimerDuration.from(id: "unknown"), .noLimit)
        XCTAssertEqual(QuickTimerDuration.from(id: nil), .noLimit)
    }

    func testSecondsMatchTitles() {
        XCTAssertEqual(QuickTimerDuration.minutes30.seconds, 1800)
        XCTAssertEqual(QuickTimerDuration.hour1.seconds, 3600)
        XCTAssertEqual(QuickTimerDuration.hours8.seconds, 28800)
        XCTAssertNil(QuickTimerDuration.noLimit.seconds)
    }
}
