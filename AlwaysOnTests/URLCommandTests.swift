import XCTest

final class URLCommandTests: XCTestCase {
    private func parse(_ string: String) -> URLCommand? {
        URLCommandParser.command(from: URL(string: string)!)
    }

    func testKnownCommands() {
        XCTAssertEqual(parse("alwayson://start"), .start)
        XCTAssertEqual(parse("alwayson://stop"), .stop)
        XCTAssertEqual(parse("alwayson://toggle"), .toggle)
        XCTAssertEqual(parse("ALWAYSON://TOGGLE"), .toggle)
    }

    func testTimerParsesMinutes() {
        XCTAssertEqual(parse("alwayson://timer?minutes=30"), .timer(minutes: 30))
        XCTAssertEqual(parse("alwayson://timer"), .timer(minutes: nil))
        XCTAssertEqual(parse("alwayson://timer?minutes=abc"), .timer(minutes: nil))
    }

    func testRejectsForeignSchemesAndUnknownCommands() {
        XCTAssertNil(parse("https://example.com/start"))
        XCTAssertNil(parse("alwayson://dance"))
        XCTAssertNil(parse("alwayson://"))
    }
}
