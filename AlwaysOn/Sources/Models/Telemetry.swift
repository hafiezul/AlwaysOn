import Foundation

/// A property value in a usage statistics event. Only plain strings, numbers,
/// and flags exist, so nothing richer (a date, a name list) can slip in.
enum TelemetryValue: Encodable, Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }
}

typealias TelemetryProperties = [String: TelemetryValue]

/// Every event AlwaysOn can send. Nothing else is ever captured.
enum TelemetryEvent: String, CaseIterable {
    /// The user turned usage statistics on
    case enabled = "telemetry_enabled"
    /// The first launch of a new version with statistics on
    case appUpdated = "app_updated"
    /// The first session after statistics were turned on
    case firstSessionStarted = "first_session_started"
    /// Once a day: settings in use and rounded counts since the last summary
    case dailySummary = "daily_summary"
}

/// Rounds counts and durations into coarse ranges before they leave the Mac
enum TelemetryBucket {
    static func count(_ value: Int) -> String {
        switch value {
        case ..<1: return "0"
        case 1: return "1"
        case 2...5: return "2-5"
        case 6...20: return "6-20"
        default: return "21+"
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let hours = seconds / 3600
        switch hours {
        case ..<(1.0 / 60): return "0"
        case ..<1: return "<1h"
        case ..<2: return "1-2h"
        case ..<4: return "2-4h"
        case ..<8: return "4-8h"
        default: return "8h+"
        }
    }
}

/// Counts kept on this Mac between daily summaries, while statistics are on
struct TelemetryCounters: Codable, Equatable {
    /// Session starts by `SessionKind` raw value
    var sessionsStarted: [String: Int] = [:]
    /// Sessions that ended on their own, by `TelemetryCounters.stopKey`
    var autoStops: [String: Int] = [:]
    /// Input events macOS refused to create
    var inputFailures = 0

    var isEmpty: Bool { self == TelemetryCounters() }

    /// Rounded counts for the daily summary. Every known key is present, so a
    /// missing feature reads as "0" rather than as absent.
    var properties: TelemetryProperties {
        var result: TelemetryProperties = [:]
        let totalSessions = sessionsStarted.values.reduce(0, +)
        result["sessions_started"] = .string(TelemetryBucket.count(totalSessions))
        for kind in SessionKind.allCases {
            result["sessions_\(kind.rawValue)"] = .string(TelemetryBucket.count(sessionsStarted[kind.rawValue] ?? 0))
        }
        for key in Self.stopKeys {
            result["stops_\(key)"] = .string(TelemetryBucket.count(autoStops[key] ?? 0))
        }
        result["input_failures"] = .string(TelemetryBucket.count(inputFailures))
        return result
    }

    static let stopKeys = ["timer", "work_hours", "away", "low_battery", "permission_revoked", "focus"]

    /// The counter key for an auto-stop reason, without its details (the
    /// battery percent or the away limit stay on the Mac)
    static func stopKey(_ reason: AutoStopEvent.Reason) -> String {
        switch reason {
        case .timerEnded: return "timer"
        case .workHoursEnded: return "work_hours"
        case .awayLimit: return "away"
        case .lowBattery: return "low_battery"
        case .permissionRevoked: return "permission_revoked"
        case .focusEnded: return "focus"
        }
    }
}

/// The JSON body of a PostHog capture request
struct TelemetryCapture: Encodable {
    let apiKey: String
    let event: String
    let distinctID: String
    let properties: TelemetryProperties
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case event
        case distinctID = "distinct_id"
        case properties
        case timestamp
    }

    /// Properties on every event. `$process_person_profile` keeps PostHog from
    /// building a person profile, and `$geoip_disable` from looking up a location.
    static func baseProperties(appVersion: String, osVersion: OperatingSystemVersion) -> TelemetryProperties {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        return [
            "$lib": .string("alwayson-macos"),
            "$process_person_profile": .bool(false),
            "$geoip_disable": .bool(true),
            "app_version": .string(appVersion),
            "os_version": .string("\(osVersion.majorVersion).\(osVersion.minorVersion)"),
            "arch": .string(architecture)
        ]
    }

    func jsonData(prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }
}
