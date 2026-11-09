import XCTest
@testable import AlwaysOnTests

final class MenuAsksTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private func launched() -> MenuAsks {
        var asks = MenuAsks()
        asks.noteLaunch(now: start)
        return asks
    }

    func testExistingUserIsAskedForStatisticsTwiceAtMost() {
        var asks = launched()
        XCTAssertEqual(asks.current(now: start, statisticsEnabled: false, hasSession: false),
                       .usageStatistics(isLastAsk: false))

        asks.postponeStatistics(now: start)
        XCTAssertNil(asks.current(now: start.addingTimeInterval(29 * day), statisticsEnabled: false, hasSession: false))
        XCTAssertEqual(asks.current(now: start.addingTimeInterval(30 * day), statisticsEnabled: false, hasSession: false),
                       .usageStatistics(isLastAsk: true))

        asks.postponeStatistics(now: start.addingTimeInterval(30 * day))
        XCTAssertTrue(asks.statisticsDeclined)
        XCTAssertNil(asks.current(now: start.addingTimeInterval(400 * day), statisticsEnabled: false, hasSession: false))
    }

    func testSetupSwitchCountsAsTheFirstAsk() {
        var asks = launched()
        asks.noteSetupOffered(now: start)
        XCTAssertNil(asks.current(now: start.addingTimeInterval(day), statisticsEnabled: false, hasSession: false))
        XCTAssertEqual(asks.current(now: start.addingTimeInterval(30 * day), statisticsEnabled: false, hasSession: false),
                       .usageStatistics(isLastAsk: true))
    }

    func testNothingShowsDuringASessionOrOnceStatisticsAreOn() {
        let asks = launched()
        XCTAssertNil(asks.current(now: start, statisticsEnabled: false, hasSession: true))
        XCTAssertNil(asks.current(now: start, statisticsEnabled: true, hasSession: false))
    }

    func testTurningStatisticsOffEndsTheAsks() {
        var asks = launched()
        asks.declineStatistics()
        XCTAssertNil(asks.current(now: start, statisticsEnabled: false, hasSession: false))
    }

    func testStarWaitsForUseAndIsAskedOnce() {
        var asks = launched()
        asks.declineStatistics()
        for _ in 0..<MenuAsks.starAfterSessions { asks.noteSessionStarted() }
        XCTAssertNil(asks.current(now: start.addingTimeInterval(13 * day), statisticsEnabled: false, hasSession: false))
        XCTAssertEqual(asks.current(now: start.addingTimeInterval(14 * day), statisticsEnabled: false, hasSession: false),
                       .githubStar)

        asks.answerStar(now: start.addingTimeInterval(14 * day))
        XCTAssertNil(asks.current(now: start.addingTimeInterval(100 * day), statisticsEnabled: false, hasSession: false))
    }

    func testStarNeedsEnoughSessions() {
        var asks = launched()
        asks.declineStatistics()
        for _ in 0..<(MenuAsks.starAfterSessions - 1) { asks.noteSessionStarted() }
        XCTAssertNil(asks.current(now: start.addingTimeInterval(60 * day), statisticsEnabled: false, hasSession: false))
    }

    func testAsksNeverFollowEachOtherWithinADay() {
        var asks = launched()
        for _ in 0..<MenuAsks.starAfterSessions { asks.noteSessionStarted() }
        let answered = start.addingTimeInterval(20 * day)
        asks.acceptStatistics(now: answered)
        XCTAssertNil(asks.current(now: answered.addingTimeInterval(day - 60), statisticsEnabled: true, hasSession: false))
        XCTAssertEqual(asks.current(now: answered.addingTimeInterval(day), statisticsEnabled: true, hasSession: false),
                       .githubStar)
    }
}
