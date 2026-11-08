import Foundation
import IOKit.ps

/// Follows the power source through IOKit's change notification, which fires
/// only when the source or charge changes, so it never polls.
final class PowerSourceMonitor {
    private(set) var state: BatteryState = .noBattery

    /// Called on the main run loop when the state changes
    var onChange: ((BatteryState) -> Void)?

    private var runLoopSource: CFRunLoopSource?

    var isEnabled: Bool { runLoopSource != nil }

    deinit { setEnabled(false) }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if enabled {
            state = Self.readState()
            let context = Unmanaged.passUnretained(self).toOpaque()
            guard let source = IOPSNotificationCreateRunLoopSource({ context in
                guard let context else { return }
                Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue().refresh()
            }, context)?.takeRetainedValue() else { return }
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        } else if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
            state = .noBattery
        }
    }

    private func refresh() {
        let next = Self.readState()
        guard next != state else { return }
        state = next
        onChange?(next)
    }

    static func readState() -> BatteryState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return .noBattery
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let onBattery = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            return BatteryState(isOnBattery: onBattery,
                                percent: BatteryState.percent(current: description[kIOPSCurrentCapacityKey] as? Int,
                                                 maximum: description[kIOPSMaxCapacityKey] as? Int))
        }
        return .noBattery
    }
}
