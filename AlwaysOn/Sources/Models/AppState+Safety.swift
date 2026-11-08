import Foundation
import AppKit
import Carbon

/// Safety stops, system sleep/lock handling, clock jumps, and the global hotkey
extension AppState {
    // MARK: - Safety Stops

    /// Runs at each simulation tick. Returns false when the session is being stopped.
    func continueAfterSafetyCheck(awayFor: TimeInterval) -> Bool {
        activityHistory.checkpoint()
        if awayLimit.isReached(awayFor: awayFor) {
            performSafetyStop(.awayLimit(awayLimit))
            return false
        }
        if batteryStopThreshold.shouldStop(powerSourceMonitor.state) {
            performSafetyStop(.lowBattery(percent: powerSourceMonitor.state.percent ?? 0))
            return false
        }
        return true
    }

    func handleBatteryChange(_ state: BatteryState) {
        guard isActive, batteryStopThreshold.shouldStop(state) else { return }
        performSafetyStop(.lowBattery(percent: state.percent ?? 0))
    }

    func performSafetyStop(_ reason: AutoStopEvent.Reason) {
        // Defer so a stop requested mid-tick or mid-start finishes that work first
        DispatchQueue.main.async { [weak self] in
            guard let self, self.hasActiveOrPausedSession else { return }
            self.stopSession()
            let event = AutoStopEvent(reason: reason, date: Date())
            self.lastAutoStop = event
            switch reason {
            case .awayLimit: self.pulseLog.record(.stoppedAway)
            case .lowBattery: self.pulseLog.record(.stoppedLowBattery)
            case .timerEnded, .workHoursEnded, .permissionRevoked, .focusEnded: break
            }
            self.notificationManager.notifySafetyStop(title: event.title, body: event.message)
        }
    }

    // MARK: - System Events

    func setupSystemEventHandling() {
        systemEventMonitor.onConditionsChanged = { [weak self] conditions in
            MainActor.assumeIsolated { self?.applySystemConditions(conditions) }
        }
        systemEventMonitor.onClockMayHaveJumped = { [weak self] in
            MainActor.assumeIsolated { self?.handleClockMayHaveJumped() }
        }
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.accessibilityPermission.refresh() }
            .store(in: &cancellables)
    }

    /// Suspends the simulator while the Mac sleeps, locks, or switches users,
    /// and resumes it, with an immediate tick, once the condition clears
    func applySystemConditions(_ conditions: SystemConditions) {
        let reason = conditions.suspensionReason(pauseWhileLocked: pauseWhileScreenLocked)
        guard reason != systemSuspension else { return }
        systemSuspension = reason
        guard isActive else { return }
        if reason != nil {
            activitySimulator.stop()
            pulseLog.record(.systemPaused)
        } else {
            restartActivitySimulatorWithCurrentSettings()
        }
    }

    /// Timers don't run during sleep and don't follow wall-clock jumps, so
    /// re-check deadlines, the schedule, and permission straight away
    func handleClockMayHaveJumped() {
        accessibilityPermission.refresh()
        expireSessionIfNeeded()
        resumeIfDue()
        refreshFocusFilter()
        workScheduleManager.checkNow()
        tickSessionState()
        rescheduleHeartbeat()
    }

    func refreshGlobalHotKey() {
        if globalHotKeyEnabled && !isRecordingHotKey {
            let registered = globalHotKeyManager.register(keyCode: globalHotKey.keyCode,
                                                          modifiers: globalHotKey.modifiers)
            if isHotKeyUnavailable == registered { isHotKeyUnavailable = !registered }
        } else {
            globalHotKeyManager.unregister()
            if isHotKeyUnavailable { isHotKeyUnavailable = false }
        }
    }
}
