import XCTest
@testable import AlwaysOnTests

final class TelemetryTests: XCTestCase {
    func testCountsAreRounded() {
        XCTAssertEqual([0, 1, 2, 5, 6, 20, 21, 500].map(TelemetryBucket.count),
                       ["0", "1", "2-5", "2-5", "6-20", "6-20", "21+", "21+"])
        XCTAssertEqual(TelemetryBucket.count(-3), "0")
    }

    func testDurationsAreRounded() {
        let hour: TimeInterval = 3600
        XCTAssertEqual([0, 30, 1800, hour, 3 * hour, 5 * hour, 12 * hour].map(TelemetryBucket.duration),
                       ["0", "0", "<1h", "1-2h", "2-4h", "4-8h", "8h+"])
    }

    func testCounterPropertiesListEveryKeyRounded() {
        var counters = TelemetryCounters()
        counters.sessionsStarted = ["manual": 3, "schedule": 1]
        counters.autoStops = [TelemetryCounters.stopKey(.lowBattery(percent: 17)): 1]
        counters.inputFailures = 40

        let properties = counters.properties
        XCTAssertEqual(properties["sessions_started"], .string("2-5"))
        XCTAssertEqual(properties["sessions_manual"], .string("2-5"))
        XCTAssertEqual(properties["sessions_schedule"], .string("1"))
        XCTAssertEqual(properties["sessions_focus"], .string("0"))
        XCTAssertEqual(properties["stops_low_battery"], .string("1"))
        XCTAssertEqual(properties["stops_away"], .string("0"))
        XCTAssertEqual(properties["input_failures"], .string("21+"))
        XCTAssertEqual(properties.count, 1 + SessionKind.allCases.count + TelemetryCounters.stopKeys.count + 1)
    }

    func testStopKeysDropDetails() {
        XCTAssertEqual(TelemetryCounters.stopKey(.lowBattery(percent: 9)), "low_battery")
        XCTAssertEqual(TelemetryCounters.stopKey(.awayLimit(.twoHours)), "away")
        let reasons: [AutoStopEvent.Reason] = [.timerEnded, .workHoursEnded, .awayLimit(.oneHour),
                                               .lowBattery(percent: 10), .permissionRevoked, .focusEnded]
        XCTAssertEqual(Set(reasons.map(TelemetryCounters.stopKey)), Set(TelemetryCounters.stopKeys))
    }

    func testCaptureBodyMatchesPostHogFormat() throws {
        var properties = TelemetryCapture.baseProperties(
            appVersion: "2.1.0",
            osVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 5, patchVersion: 1))
        properties["source"] = .string("settings")
        let capture = TelemetryCapture(apiKey: "phc_test", event: TelemetryEvent.enabled.rawValue,
                                       distinctID: "install-id", properties: properties,
                                       timestamp: Date(timeIntervalSince1970: 0))

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: capture.jsonData()) as? [String: Any])
        XCTAssertEqual(json["api_key"] as? String, "phc_test")
        XCTAssertEqual(json["event"] as? String, "telemetry_enabled")
        XCTAssertEqual(json["distinct_id"] as? String, "install-id")
        XCTAssertEqual(json["timestamp"] as? String, "1970-01-01T00:00:00Z")

        let sent = try XCTUnwrap(json["properties"] as? [String: Any])
        XCTAssertEqual(sent["$process_person_profile"] as? Bool, false)
        XCTAssertEqual(sent["$geoip_disable"] as? Bool, true)
        XCTAssertEqual(sent["os_version"] as? String, "14.5", "patch version is dropped")
        XCTAssertEqual(sent["app_version"] as? String, "2.1.0")
        XCTAssertEqual(sent["source"] as? String, "settings")
    }
}
