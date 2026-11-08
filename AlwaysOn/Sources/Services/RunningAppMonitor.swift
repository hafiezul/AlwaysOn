import AppKit

/// Keeps a live count of running apps by bundle ID from launch and quit
/// notifications, so the target-app gate answers from memory instead of
/// walking every running process on each simulation tick. Observes only
/// while enabled, so it costs nothing when the target-app gate is off.
final class RunningAppMonitor {
    private let notificationCenter: NotificationCenter
    private let runningBundleIDs: () -> [String]
    private let bundleIDOf: (Notification) -> String?
    private var counts: [String: Int] = [:]
    private var tokens: [NSObjectProtocol] = []

    private(set) var isEnabled = false

    /// Called on the main queue when an app starts or stops running, after
    /// the counts change. Not called while disabled.
    var onChange: (() -> Void)?

    /// - Parameters:
    ///   - notificationCenter: Source of launch and quit notifications
    ///   - runningBundleIDs: Snapshot used to seed counts when monitoring starts
    ///   - bundleIDOf: Reads the app's bundle ID from a launch or quit notification
    init(notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         runningBundleIDs: @escaping () -> [String] = {
             NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
         },
         bundleIDOf: @escaping (Notification) -> String? = {
             ($0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
         }) {
        self.notificationCenter = notificationCenter
        self.runningBundleIDs = runningBundleIDs
        self.bundleIDOf = bundleIDOf
    }

    deinit { setEnabled(false) }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            counts = runningBundleIDs().reduce(into: [:]) { $0[$1, default: 0] += 1 }
            tokens = [
                notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                               object: nil, queue: .main) { [weak self] note in
                    self?.adjust(note, by: 1)
                },
                notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                               object: nil, queue: .main) { [weak self] note in
                    self?.adjust(note, by: -1)
                }
            ]
        } else {
            tokens.forEach(notificationCenter.removeObserver)
            tokens = []
            counts = [:]
        }
    }

    /// Whether any of the given bundle IDs is running. While disabled this
    /// falls back to a fresh snapshot so callers always get a correct answer.
    func isAnyRunning(_ bundleIDs: Set<String>) -> Bool {
        guard isEnabled else { return runningBundleIDs().contains(where: bundleIDs.contains) }
        return bundleIDs.contains { counts[$0, default: 0] > 0 }
    }

    private func adjust(_ note: Notification, by delta: Int) {
        guard let bundleID = bundleIDOf(note) else { return }
        let previous = counts[bundleID, default: 0]
        let next = previous + delta
        counts[bundleID] = next > 0 ? next : nil
        // Only the first launch or last quit changes whether the app runs
        if (previous > 0) != (next > 0) { onChange?() }
    }
}
