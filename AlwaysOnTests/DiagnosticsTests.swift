import XCTest
@testable import AlwaysOnTests

final class DiagnosticsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func report(entries: [PulseLog.Entry] = [], counts: [PulseLog.Outcome: Int] = [:],
                        settings: TelemetryProperties = [:]) -> DiagnosticReport {
        DiagnosticReport(appVersion: "1.14.0", buildNumber: "321", osVersion: "26.1.0", architecture: "arm64",
                         state: "active", source: "timer", isSuspended: false, hasAccessibilityPermission: true,
                         settings: settings, outcomeCounts: counts, recentEntries: entries, generatedAt: now)
    }

    func testHeaderNamesVersionPlatformPermissionAndSession() {
        let text = report().text
        XCTAssertTrue(text.contains("- Version: 1.14.0 (321)"))
        XCTAssertTrue(text.contains("- macOS: 26.1.0 (arm64)"))
        XCTAssertTrue(text.contains("- Accessibility permission: granted"))
        XCTAssertTrue(text.contains("- Session: active (timer)"))
    }

    func testSettingsAreSortedAndRendered() {
        let text = report(settings: ["b_flag": .bool(true), "a_count": .int(3), "c_text": .string("fixed")]).text
        let a = text.range(of: "- a_count: 3")!, b = text.range(of: "- b_flag: yes")!, c = text.range(of: "- c_text: fixed")!
        XCTAssertTrue(a.lowerBound < b.lowerBound && b.lowerBound < c.lowerBound)
    }

    func testCountsSkipZeroAndUsePulseLogWording() {
        let text = report(counts: [.posted: 10, .inputNotRegistered: 2, .noTarget: 0]).text
        XCTAssertTrue(text.contains("- Input posted: 10"))
        XCTAssertTrue(text.contains("- Input had no effect: 2"))
        XCTAssertFalse(text.contains("Skipped: no target app"))
    }

    func testRecentEntriesUseRelativeAgesAndAreCapped() {
        let entries = (0..<40).map { PulseLog.Entry(date: now.addingTimeInterval(-Double($0) * 45), outcome: .posted) }
        let text = report(entries: entries).text
        XCTAssertTrue(text.contains("- 0s ago: Input posted"))
        XCTAssertTrue(text.contains("- 45s ago: Input posted"))
        XCTAssertEqual(text.components(separatedBy: ": Input posted").count - 1, DiagnosticReport.recentLimit)
    }

    func testAgesFormat() {
        XCTAssertEqual([0, 59, 60, 3599, 3600, 7500].map { DiagnosticReport.ago(TimeInterval($0)) },
                       ["0s ago", "59s ago", "1m ago", "59m ago", "1h 0m ago", "2h 5m ago"])
        XCTAssertEqual(DiagnosticReport.ago(-5), "0s ago")
    }

    func testEmptyReportSaysNone() {
        XCTAssertEqual(report().text.components(separatedBy: "- none").count - 1, 2)
    }
}
