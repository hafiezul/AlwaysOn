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

    func testPauseParsesOptionalMinutes() {
        XCTAssertEqual(parse("alwayson://pause"), .pause(minutes: nil))
        XCTAssertEqual(parse("alwayson://pause?minutes=15"), .pause(minutes: 15))
        XCTAssertEqual(parse("alwayson://pause?MINUTES=1440"), .pause(minutes: 1440))
        for bad in ["0", "1441", "abc", "", "-5"] {
            XCTAssertNil(parse("alwayson://pause?minutes=\(bad)"), bad)
        }
        XCTAssertNil(parse("alwayson://pause?minutes=5&minutes=10"))
    }

    func testRejectsForeignSchemesAndUnknownCommands() {
        XCTAssertNil(parse("https://example.com/start"))
        XCTAssertNil(parse("alwayson://dance"))
        XCTAssertNil(parse("alwayson://"))
    }
    func testCommandTokens() {
        let value = "11111111-1111-1111-1111-111111111111"
        let token = UUID(uuidString: value)!
        XCTAssertEqual(parse("alwayson://run?token=\(value)"), .run(token: token))
        XCTAssertEqual(parse("alwayson://finish?token=\(value)"), .finish(token: token))
        for action in ["run", "finish"] {
            for query in ["", "?token", "?token=", "?token=nope", "?token=\(value)&token=\(value)", "?token=\(value)&TOKEN=bad"] {
                XCTAssertNil(parse("alwayson://\(action)\(query)"))
            }
        }
    }
    func testUntilDateValidation() {
        let date = Date(timeIntervalSince1970: 4102444800)
        XCTAssertEqual(parse("alwayson://until?date=2100-01-01T00:00:00Z"), .until(date: date))
        XCTAssertEqual(parse("alwayson://until?date=2100-01-01T00:00:00.000Z"), .until(date: date))
        for query in ["", "?date=", "?date=bad", "?date=2000-01-01T00:00:00Z",
                      "?date=2100-01-01T00:00:00Z&DATE=2100-01-01T00:00:00Z"] {
            XCTAssertNil(parse("alwayson://until\(query)"))
        }
    }

    func testProfileRequiresOneNonEmptyName() {
        XCTAssertEqual(parse("alwayson://profile?name=Work"), .profile(name: "Work"))
        XCTAssertEqual(parse("alwayson://profile?NAME=Deep%20Work"), .profile(name: "Deep Work"))
        XCTAssertEqual(parse("alwayson://profile?name=%20Home%20"), .profile(name: "Home"))
        for query in ["", "?name", "?name=", "?name=%20", "?name=A&name=B", "?profile=Work"] {
            XCTAssertNil(parse("alwayson://profile\(query)"), query)
        }
    }
}
