import Foundation

/// A plain-text report for bug reports. Built only from values that are safe
/// to share: version numbers, on/off settings, counts, and AlwaysOn's own
/// input attempts. Never names, networks, events, apps, or times of day.
struct DiagnosticReport {
    var appVersion: String
    var buildNumber: String
    /// "major.minor.patch"
    var osVersion: String
    var architecture: String
    /// "active", "paused", or "off"
    var state: String
    /// What started the session ("manual", "timer", ...); nil when off
    var source: String?
    var isSuspended: Bool
    var hasAccessibilityPermission: Bool
    /// From AppState.telemetrySettingsSnapshot(), already free of personal data
    var settings: TelemetryProperties
    var outcomeCounts: [PulseLog.Outcome: Int]
    /// Newest first
    var recentEntries: [PulseLog.Entry]
    var generatedAt: Date

    /// How many recent attempts the report lists
    static let recentLimit = 30

    var text: String {
        var lines: [String] = []
        lines.append("### AlwaysOn diagnostics")
        lines.append("- Version: \(appVersion) (\(buildNumber))")
        lines.append("- macOS: \(osVersion) (\(architecture))")
        lines.append("- Accessibility permission: \(hasAccessibilityPermission ? "granted" : "missing")")
        lines.append("- Session: \(state)\(source.map { " (\($0))" } ?? "")\(isSuspended ? ", on hold (asleep, locked, or switched user)" : "")")
        lines.append("")
        lines.append("### Settings")
        for key in settings.keys.sorted() {
            lines.append("- \(key): \(Self.render(settings[key]!))")
        }
        lines.append("")
        lines.append("### Pulse Log totals since launch")
        let counted = outcomeCounts.filter { $0.value > 0 }
        if counted.isEmpty {
            lines.append("- none")
        } else {
            for (outcome, count) in counted.sorted(by: { $0.value > $1.value || ($0.value == $1.value && Self.name(of: $0.key) < Self.name(of: $1.key)) }) {
                lines.append("- \(Self.name(of: outcome)): \(count)")
            }
        }
        lines.append("")
        lines.append("### Last \(Self.recentLimit) attempts, newest first")
        if recentEntries.isEmpty { lines.append("- none") }
        for entry in recentEntries.prefix(Self.recentLimit) {
            lines.append("- \(Self.ago(generatedAt.timeIntervalSince(entry.date))): \(Self.name(of: entry.outcome))")
        }
        return lines.joined(separator: "\n")
    }

    static func render(_ value: TelemetryValue) -> String {
        switch value {
        case .string(let text): return text
        case .int(let number): return String(number)
        case .bool(let flag): return flag ? "yes" : "no"
        }
    }

    /// The outcome's Pulse Log wording, e.g. "Input had no effect"
    static func name(of outcome: PulseLog.Outcome) -> String {
        PulseLog.Entry(date: Date(timeIntervalSince1970: 0), outcome: outcome).summary
    }

    /// Relative age such as "45s ago", "12m ago", or "2h 5m ago"
    static func ago(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total)s ago" }
        if total < 3600 { return "\(total / 60)m ago" }
        return "\(total / 3600)h \((total % 3600) / 60)m ago"
    }
}
