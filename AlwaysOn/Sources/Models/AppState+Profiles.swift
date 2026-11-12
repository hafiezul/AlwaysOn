import Foundation
import Combine

/// Profiles, work hours automation, and switching profiles by Wi-Fi network
extension AppState {
    // MARK: - Profiles

    func applyProfile(_ profile: Profile) {
        stopSession()
        isApplyingProfile = true
        suppressScheduleAutoStart = true
        defer {
            isApplyingProfile = false
            suppressScheduleAutoStart = false
        }

        activityInterval = profile.activityInterval > 0 ? profile.activityInterval : Defaults.activityInterval
        activityMethod = profile.activityMethod
        defaultTimerDuration = profile.defaultTimerDuration
        workScheduleManager.schedule = profile.workSchedule
        if let behavior = profile.behavior {
            pulsePacing = behavior.pulsePacing
            adaptivePostAfter = behavior.adaptivePostAfter
            simulateOnlyWhenIdle = behavior.simulateOnlyWhenIdle
            requireTargetApp = behavior.requireTargetApp
            targetApps = Set(behavior.targetApps)
            sleepPrevention = behavior.sleepPrevention
            awayLimit = behavior.awayLimit
            batteryStopThreshold = behavior.batteryStopThreshold
        }
        quickTimerEndTime = nil
        quickTimerRemaining = 0
    }

    func switchProfile(_ id: UUID) {
        guard id != profileManager.activeProfileId else { return }
        // Any switch, by hand or by network, settles the current network's rule
        pendingNetworkProfileId = nil
        handledNetwork = wifiMonitor.currentNetwork

        syncActiveProfileSettings()
        let wasActive = isActive || activeSessionDuration > 0

        // Priority: Manual user action > Profile switch > Work Schedule
        stopSession()

        guard let newProfile = profileManager.switchProfile(to: id) else { return }
        applyProfile(newProfile)

        if wasActive {
            notificationManager.notifyProfileSwitchedDuringSession(newProfileName: newProfile.name)
        }
    }

    func setupProfileSync() {
        workScheduleManager.$schedule
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: WorkSchedule) in
                self?.syncActiveProfileSettings()
            }
            .store(in: &cancellables)
    }

    /// The eight per-profile behavior settings as they are right now
    var currentProfileBehavior: ProfileBehavior {
        ProfileBehavior(pulsePacingId: pulsePacing.rawValue,
                        adaptivePostAfterSeconds: adaptivePostAfter.rawValue,
                        simulateOnlyWhenIdle: simulateOnlyWhenIdle,
                        requireTargetApp: requireTargetApp,
                        targetApps: targetApps.sorted(),
                        sleepPreventionId: sleepPrevention.rawValue,
                        awayLimitHours: awayLimit.rawValue,
                        batteryStopPercent: batteryStopThreshold.rawValue)
    }

    func syncActiveProfileSettings() {
        guard !isApplyingProfile else { return }
        profileManager.updateProfileSettings(
            profileManager.activeProfileId,
            activityInterval: activityInterval,
            activityMethod: activityMethod,
            defaultTimerDuration: defaultTimerDuration,
            workSchedule: workScheduleManager.schedule,
            behavior: currentProfileBehavior
        )
    }

    // MARK: - Skipped Days

    /// Skips work hours on a day, or brings them back. Skipping today ends a
    /// session that work hours started, like work hours ending.
    func setWorkHoursSkipped(_ skipped: Bool, on date: Date = Date()) {
        var schedule = workScheduleManager.schedule
        schedule.pruneSkippedDays(before: Date())
        schedule.setSkipped(skipped, on: date)
        workScheduleManager.schedule = schedule
    }

    /// What the menu can offer for today's work hours
    enum TodayScheduleAction { case skip, undoSkip }

    var todayScheduleAction: TodayScheduleAction? {
        let schedule = workScheduleManager.schedule
        let now = Date()
        guard schedule.isEnabled, schedule.isWorkday(now) else { return nil }
        if schedule.isSkipped(now) { return .undoSkip }
        guard let end = schedule.workdayEnd(on: now), end > now else { return nil }
        return .skip
    }

    // MARK: - Automation Handlers
    
    func handleWorkScheduleChange(isWithinSchedule: Bool) {
        guard workScheduleManager.schedule.isEnabled else { return }
        
        if isWithinSchedule {
            guard !suppressScheduleAutoStart else { return }
            
            // Auto-enable only when there is no active or paused session to preserve manual control.
            accessibilityPermission.refresh()
            if !hasActiveOrPausedSession && hasAccessibilityPermission {
                stopSession()
                sessionSource = .workSchedule(profileName: profileManager.activeProfile?.name ?? "")
                isActive = true
                notificationManager.notifyWorkScheduleStarted()
            }
        } else {
            guard isScheduleControlledSession && hasActiveOrPausedSession else { return }
            
            stopSession()
            lastAutoStop = AutoStopEvent(reason: .workHoursEnded, date: Date())
            notificationManager.notifyWorkScheduleEnded()
        }
    }

    func setupAutomationObservers() {
        // Work Schedule: Auto-enable/disable based on schedule
        workScheduleManager.onScheduleStateChanged = { [weak self] (isWithinSchedule: Bool) in
            guard let self else { return }
            Task { @MainActor in
                self.handleWorkScheduleChange(isWithinSchedule: isWithinSchedule)
            }
        }
    }

    // MARK: - Network Profiles

    func setupNetworkProfiles() {
        wifiMonitor.setMonitoring(switchProfilesByNetwork)
        // A switch that waited for a session applies once the session ends
        Publishers.CombineLatest($isActive, $sessionSource)
            .debounce(for: .zero, scheduler: DispatchQueue.main)
            .sink { [weak self] _, _ in
                guard let self, self.pendingNetworkProfileId != nil, !self.hasActiveOrPausedSession else { return }
                self.applyNetworkProfile()
            }
            .store(in: &cancellables)
    }

    /// Makes the current Wi-Fi network switch to the given profile, and applies it now
    func useCurrentNetwork(for profileID: UUID) {
        guard let network = wifiMonitor.currentNetwork else { return }
        profileManager.assignNetwork(network, to: profileID)
        handledNetwork = nil
        applyNetworkProfile()
    }

    /// Switches to the profile listed for the current network, once per network.
    /// A running session is never interrupted: the switch waits for it to end.
    func applyNetworkProfile() {
        guard switchProfilesByNetwork, let network = wifiMonitor.currentNetwork, network != handledNetwork else { return }
        guard let target = NetworkProfileRule.profileID(forNetwork: network, in: profileManager.profiles),
              target != profileManager.activeProfileId else {
            pendingNetworkProfileId = nil
            handledNetwork = network
            return
        }
        if hasActiveOrPausedSession {
            pendingNetworkProfileId = target
            return
        }
        switchProfile(target)
        let name = profileManager.activeProfile?.name ?? ""
        lastNetworkSwitch = NetworkSwitchEvent(profileName: name, network: network, date: Date())
        notificationManager.notifyProfileSwitchedByNetwork(profileName: name, network: network)
        // Let the new profile's work hours start now if they are under way
        DispatchQueue.main.async { [weak self] in
            guard let self, self.workScheduleManager.isWithinSchedule else { return }
            self.handleWorkScheduleChange(isWithinSchedule: true)
        }
    }
}
