import Foundation
import IOKit.pwr_mgt

/// Holds at most one IOKit power assertion. An assertion costs nothing while
/// held: it only tells the power manager not to idle-sleep, with no timers.
/// macOS releases it automatically if AlwaysOn quits or crashes.
final class PowerAssertionManager {
    private(set) var level: PowerAssertionLevel?
    private var assertionID: IOPMAssertionID = 0

    deinit { release() }

    /// Holds the given assertion, replacing any other; nil releases it
    func hold(_ newLevel: PowerAssertionLevel?) {
        guard newLevel != level else { return }
        release()
        guard let newLevel else { return }

        let type: String
        switch newLevel {
        case .system: type = kIOPMAssertionTypePreventUserIdleSystemSleep
        case .display: type = kIOPMAssertionTypePreventUserIdleDisplaySleep
        }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(type as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "AlwaysOn is keeping you online" as CFString,
                                                 &id)
        guard result == kIOReturnSuccess else { return }
        assertionID = id
        level = newLevel
    }

    private func release() {
        guard level != nil else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        level = nil
    }
}
