import XCTest
@testable import AlwaysOnTests

final class UpdateCheckerTests: XCTestCase {
    func testVersionComparisonPadsMissingComponents() {
        XCTAssertTrue(UpdateChecker.isVersion("1.3", newerThan: "1.2.9"))
        XCTAssertFalse(UpdateChecker.isVersion("1.2", newerThan: "1.2.9"))
        XCTAssertFalse(UpdateChecker.isVersion("1.2.3", newerThan: "1.2.3"))
    }

    func testVersionComparisonHonorsComponentOrder() {
        XCTAssertTrue(UpdateChecker.isVersion("2.0.0", newerThan: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isVersion("1.10.0", newerThan: "1.9.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.9.0", newerThan: "1.10.0"))
    }

    func testNormalizationDropsOnlyLeadingV() {
        XCTAssertEqual(UpdateChecker.normalizeVersion("  V1.2.3 "), "1.2.3")
        XCTAssertEqual(UpdateChecker.normalizeVersion("v2.0.0-release-notes"), "2.0.0-release-notes")
    }
}
