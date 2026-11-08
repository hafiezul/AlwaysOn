import Foundation
import Combine

/// Energy-aware pacing and sleep prevention
extension AppState {
    func setupPacingAndPower() {
        energyMonitor.onChange = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.energyState = state
                // Applies from the next tick; no extra input on the change itself
                self.activitySimulator.schedule = self.currentPulseSchedule
            }
        }

        // The target-app rule decides whether adaptive pacing holds the display
        runningAppMonitor.onChange = { [weak self] in
            MainActor.assumeIsolated { self?.refreshPowerAssertion() }
        }

        // Coalesce the several changes one action makes into one update.
        // @Published emits before the new value is stored, so the deferred
        // sink reads the properties rather than the emitted values.
        Publishers.CombineLatest4($isActive, $systemSuspension, $pulsePacing, $sleepPrevention)
            .combineLatest($requireTargetApp, $targetApps)
            .debounce(for: .zero, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshPowerAssertion() }
            .store(in: &cancellables)
    }

    /// Holds the power assertion the current session needs, or releases it
    func refreshPowerAssertion() {
        let targetAppReady = !requireTargetApp || runningAppMonitor.isAnyRunning(targetApps)
        powerAssertions.hold(SleepPreventionPolicy.requiredLevel(setting: sleepPrevention,
                                                                 pacing: pulsePacing,
                                                                 isActive: isActive,
                                                                 suspension: systemSuspension,
                                                                 targetAppReady: targetAppReady))
    }

    /// One line for Settings describing what pacing is doing right now
    var pacingStatus: String {
        let schedule = currentPulseSchedule
        switch schedule.pacing {
        case .fixed:
            let seconds = Int(schedule.effectiveInterval)
            let interval = seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s"
            if schedule.savesEnergy, let reason = energyState.summary {
                return "\(reason), so input is sent every \(interval) instead."
            }
            return "Input is sent every \(interval)."
        case .adaptive:
            let seconds = Int(schedule.postAfter)
            let wait = seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s"
            var line = "Input is sent only after \(wait) without keyboard or mouse use."
            if schedule.postAfter < adaptivePostAfter.seconds {
                line += " Shortened so it lands before your screen saver starts."
            }
            return line
        }
    }
}
