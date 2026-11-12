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

extension PowerAssertionManager {
    /// Whether another process holds an assertion that keeps the display on.
    /// Browsers, QuickTime, IINA and VLC hold one while video plays, so this
    /// is how AlwaysOn tells playback is on screen. AlwaysOn's own assertion
    /// is ignored. Reads a snapshot from the power manager; no polling.
    static func otherProcessKeepsDisplayAwake(excluding pid: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return false }
        let displayTypes: Set<String> = [kIOPMAssertionTypePreventUserIdleDisplaySleep,
                                         kIOPMAssertionTypeNoDisplaySleep]
        return byProcess.contains { processID, assertions in
            processID.int32Value != pid && assertions.contains { assertion in
                guard let type = assertion[kIOPMAssertionTypeKey] as? String,
                      displayTypes.contains(type) else { return false }
                // A level of 0 means the assertion exists but is switched off
                return (assertion[kIOPMAssertionLevelKey] as? Int).map { $0 != 0 } ?? true
            }
        }
    }
}
