import Foundation

/// Follows Low Power Mode and thermal pressure through ProcessInfo's change
/// notifications, so it never polls. Callbacks arrive on the main queue.
final class EnergyMonitor {
    private(set) var state: EnergyState

    /// Called when Low Power Mode or the thermal state changes
    var onChange: ((EnergyState) -> Void)?

    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter = .default) {
        self.center = center
        state = Self.readState()
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange,
                     ProcessInfo.thermalStateDidChangeNotification] {
            // Both post on arbitrary threads; hop to main before touching state
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
    }

    deinit {
        tokens.forEach(center.removeObserver)
    }

    private func refresh() {
        let next = Self.readState()
        guard next != state else { return }
        state = next
        onChange?(next)
    }

    static func readState() -> EnergyState {
        let info = ProcessInfo.processInfo
        let thermal = info.thermalState
        return EnergyState(isLowPowerMode: info.isLowPowerModeEnabled,
                           isThermallyConstrained: thermal == .serious || thermal == .critical)
    }
}

/// The user's screen saver delay, which adaptive pacing must stay under
enum ScreenSaverSettings {
    /// Seconds of idle time before the screen saver starts, nil when it never does
    static func idleDelay() -> TimeInterval? {
        let value = CFPreferencesCopyValue("idleTime" as CFString,
                                           "com.apple.screensaver" as CFString,
                                           kCFPreferencesCurrentUser,
                                           kCFPreferencesCurrentHost)
        guard let number = value as? NSNumber, number.doubleValue > 0 else { return nil }
        return number.doubleValue
    }
}
