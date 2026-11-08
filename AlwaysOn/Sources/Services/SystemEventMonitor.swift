import AppKit
import CoreGraphics

/// Observes sleep, wake, screen lock, user switching, and clock changes.
/// Every callback arrives on the main queue.
final class SystemEventMonitor {
    /// Current system conditions; updated before onConditionsChanged runs
    private(set) var conditions: SystemConditions

    /// Called whenever sleep, lock, or session state changes
    var onConditionsChanged: ((SystemConditions) -> Void)?

    /// Called after the Mac wakes or the wall clock jumps (time zone, manual
    /// change, day rollover), when deadlines and schedules need re-checking
    var onClockMayHaveJumped: (() -> Void)?

    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        conditions = SystemConditions(isAsleep: false,
                                      isSessionInactive: !Self.sessionIsOnConsole(),
                                      isScreenLocked: Self.screenIsLocked())

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.isAsleep = true }
        observe(workspace, NSWorkspace.didWakeNotification, clockJump: true) { $0.isAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.isSessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.isSessionInactive = false }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.isScreenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.isScreenLocked = false }

        let local = NotificationCenter.default
        for name in [Notification.Name.NSSystemClockDidChange,
                     .NSSystemTimeZoneDidChange,
                     .NSCalendarDayChanged] {
            observe(local, name, clockJump: true, update: nil)
        }
    }

    deinit {
        for (center, token) in tokens { center.removeObserver(token) }
    }

    private func observe(_ center: NotificationCenter,
                         _ name: Notification.Name,
                         clockJump: Bool = false,
                         update: ((inout SystemConditions) -> Void)?) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if let update {
                var next = self.conditions
                update(&next)
                if next != self.conditions {
                    self.conditions = next
                    self.onConditionsChanged?(next)
                }
            }
            if clockJump { self.onClockMayHaveJumped?() }
        }
        tokens.append((center, token))
    }

    // MARK: - Launch-time state

    private static func sessionDictionary() -> [String: Any]? {
        CGSessionCopyCurrentDictionary() as? [String: Any]
    }

    private static func screenIsLocked() -> Bool {
        sessionDictionary()?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private static func sessionIsOnConsole() -> Bool {
        sessionDictionary()?[kCGSessionOnConsoleKey as String] as? Bool ?? true
    }
}
