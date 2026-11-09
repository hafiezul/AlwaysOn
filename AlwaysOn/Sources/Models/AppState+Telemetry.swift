import AppKit
import Combine

/// The settings part of the daily usage summary. Only choices and flags:
/// never profile names, Wi-Fi names, calendar events, target app names,
/// schedule times, or the hotkey itself.
extension AppState {
    func setupTelemetry() {
        telemetry.summaryProvider = { [weak self] in
            self?.telemetrySettingsSnapshot() ?? [:]
        }
        // Turning statistics off is an answer; the menu won't ask again
        telemetry.$isEnabled
            .removeDuplicates()
            .dropFirst()
            .filter { !$0 }
            .sink { [weak self] _ in self?.menuAsks.declineStatistics() }
            .store(in: &cancellables)
        telemetry.start()
    }

    // MARK: - Menu Asks

    var currentMenuAsk: MenuAsks.Ask? {
        menuAsks.current(now: Date(), statisticsEnabled: telemetry.isEnabled,
                         hasSession: hasActiveOrPausedSession || !hasAccessibilityPermission)
    }

    func acceptStatisticsFromMenu() {
        menuAsks.acceptStatistics(now: Date())
        telemetry.setEnabled(true, source: .menu)
    }

    func postponeStatisticsFromMenu() {
        menuAsks.postponeStatistics(now: Date())
    }

    func answerStarRequest(openRepository: Bool) {
        menuAsks.answerStar(now: Date())
        if openRepository { NSWorkspace.shared.open(AppUpdateRepository.repositoryURL) }
    }

    func telemetrySettingsSnapshot(now: Date = Date()) -> TelemetryProperties {
        let profiles = profileManager.profiles
        let lastDay = DateInterval(start: now.addingTimeInterval(-24 * 60 * 60), end: now)
        let presetIntervals: Set<TimeInterval> = [30, 45, 60, 120, 300]

        return [
            "online_time_last_24h": .string(TelemetryBucket.duration(activityHistory.ledger.onlineTime(in: lastDay, now: now))),
            "activity_method": .string(activityMethod.rawValue),
            "pulse_pacing": .string(pulsePacing.rawValue),
            "activity_interval": .string(presetIntervals.contains(activityInterval) ? String(Int(activityInterval)) : "custom"),
            "default_timer_set": .bool(defaultTimerDuration.seconds != nil),
            "only_when_idle": .bool(simulateOnlyWhenIdle),
            "require_target_app": .bool(requireTargetApp),
            "target_app_count": .string(TelemetryBucket.count(requireTargetApp ? targetApps.count : 0)),
            "pause_while_locked": .bool(pauseWhileScreenLocked),
            "away_limit_hours": .int(awayLimit.rawValue),
            "battery_stop_percent": .int(batteryStopThreshold.rawValue),
            "sleep_prevention": .string(sleepPrevention.rawValue),
            "save_energy": .bool(savesEnergyWhenConstrained),
            "menu_bar_label": .string(menuBarLabelStyle.rawValue),
            "global_hotkey": .bool(globalHotKeyEnabled),
            "custom_hotkey": .bool(globalHotKey != .default),
            "profile_count": .string(TelemetryBucket.count(profiles.count)),
            "work_schedule": .bool(profiles.contains { $0.workSchedule.isEnabled }),
            "wifi_profiles": .bool(switchProfilesByNetwork),
            "launch_at_login": .bool(LaunchAtLoginManager.isEnabled),
            "notifications": .bool(notificationManager.isEnabled && notificationManager.authorizationStatus == .authorized),
            "location_allowed": .bool(wifiMonitor.locationAccess == .granted),
            "calendar_allowed": .bool(CalendarEventProvider.currentAccessState() == .granted),
            "cli_installed": .bool(CLIInstallation().status == .current),
            "auto_update_checks": .bool(AppUpdater.shared.automaticallyChecksForUpdates)
        ]
    }
}
