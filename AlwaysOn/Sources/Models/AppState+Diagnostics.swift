import Foundation

/// The diagnostics report for Settings > About. Settings come from the
/// usage-statistics snapshot, so the same privacy rules apply.
extension AppState {
    func diagnosticReport(now: Date = Date()) -> DiagnosticReport {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let status = sessionStatus
        return DiagnosticReport(
            appVersion: Bundle.main.appVersion,
            buildNumber: Bundle.main.buildNumber,
            osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            architecture: architecture,
            state: status.state.rawValue,
            source: status.source,
            isSuspended: status.isSuspended,
            hasAccessibilityPermission: status.hasAccessibilityPermission,
            settings: telemetrySettingsSnapshot(now: now),
            outcomeCounts: pulseLog.counts,
            recentEntries: Array(pulseLog.history.reversed()),
            generatedAt: now
        )
    }
}
