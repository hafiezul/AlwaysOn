import Foundation

/// alwayson:// URL commands, shared by the CLI, launchers, and Shortcuts
extension AppState {
    // MARK: - URL Commands
    
    func applyURLCommand(_ command: URLCommand) {
        accessibilityPermission.refresh()
        switch command {
        case .run(let token):
            guard hasAccessibilityPermission else { accessibilityPermission.request(); return }
            replaceSession(source: .runningCommand(token: token, now: Date()))
        case .finish(let token):
            if sessionEndCondition.matchesFinish(token: token) { stopSession() }
        case .start:
            sessionSource = sessionSource?.relinquishingCommand
            if !isActive {
                if hasAccessibilityPermission {
                    if expireSessionIfNeeded() { return }
                    switch sessionSource {
                    case .until: break
                    default: sessionSource = .manual
                    }
                    isActive = true
                } else {
                    accessibilityPermission.request()
                }
            }
        case .stop:
            stopSession()
        case .toggle:
            toggle()
        case .until(let date):
            guard date.timeIntervalSince1970.isFinite, date > Date() else { return }
            guard hasAccessibilityPermission else { accessibilityPermission.request(); return }
            startUntil(date: date)
        case .timer(let minutes):
            let duration: QuickTimerDuration
            if let minutes {
                let clamped = min(max(minutes, QuickTimerDuration.customMinutesRange.lowerBound),
                                  QuickTimerDuration.customMinutesRange.upperBound)
                duration = .custom(minutes: clamped)
            } else {
                duration = defaultTimerDuration
            }
            startWithQuickTimer(duration)
        case .pause(let minutes):
            pause(for: minutes.map { TimeInterval($0 * 60) })
        }
    }
}
