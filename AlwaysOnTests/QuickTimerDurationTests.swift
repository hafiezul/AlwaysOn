import XCTest
@testable import AlwaysOnTests

final class QuickTimerDurationTests: XCTestCase {
    func testIdentityAndPresetOrder() {
        XCTAssertNotEqual(QuickTimerDuration.custom(minutes: 60), .hour1)
        XCTAssertEqual(QuickTimerDuration.custom(minutes: 60), .custom(minutes: 60))
        XCTAssertNotEqual(QuickTimerDuration.custom(minutes: 60), .custom(minutes: 61))
        let durations: Set<QuickTimerDuration> = [.hour1, .custom(minutes: 60), .custom(minutes: 60), .custom(minutes: 61)]
        XCTAssertEqual(durations.count, 3)
        XCTAssertTrue(durations.contains(.hour1))
        XCTAssertTrue(durations.contains(.custom(minutes: 60)))
        XCTAssertTrue(durations.contains(.custom(minutes: 61)))
        XCTAssertEqual(QuickTimerDuration.allCases, [.minutes30, .hour1, .hours2, .hours4, .hours8, .noLimit])
    }

    func testLegacyPresetIdsRoundTrip() {
        XCTAssertEqual(QuickTimerDuration.allCases.map(\.id), ["30m", "1h", "2h", "4h", "8h", "none"])
        XCTAssertEqual(["30m", "1h", "2h", "4h", "8h", "none"].map { QuickTimerDuration.from(id: $0) },
                       [.minutes30, .hour1, .hours2, .hours4, .hours8, .noLimit])
    }

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
