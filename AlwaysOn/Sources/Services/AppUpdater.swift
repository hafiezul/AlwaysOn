import AppKit
import Combine
import Sparkle

/// Sparkle-backed automatic updates.
///
/// Release builds carry an EdDSA public key (`SUPublicEDKey`) and read the
/// appcast attached to the latest GitHub release. Sparkle installs an update only
/// when its EdDSA signature checks out and the new app is signed by the same
/// certificate as the running one, so Accessibility access carries over.
///
/// Local and CI builds have no key; for those the updater stays off and the
/// Updates pane falls back to the manual GitHub release check.
final class AppUpdater: NSObject, ObservableObject {
    static let shared = AppUpdater()

    /// Whether this build can update itself
    let isConfigured: Bool

    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController?
    private var cancellables: Set<AnyCancellable> = []

    /// Our windows lowered to `.normal` for the current update session
    private let loweredWindows = NSHashTable<NSWindow>.weakObjects()

    private var updater: SPUUpdater? { controller?.updater }

    private override init() {
        let key = Bundle.main.infoPlistString(forKey: "SUPublicEDKey")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        isConfigured = !key.isEmpty && !key.hasPrefix("$(")
        super.init()

        guard isConfigured else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        self.controller = controller

        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &cancellables)
    }

    var lastUpdateCheckDate: Date? { updater?.lastUpdateCheckDate }

    var automaticallyChecksForUpdates: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            updater?.automaticallyChecksForUpdates = newValue
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater?.automaticallyDownloadsUpdates ?? false }
        set {
            objectWillChange.send()
            updater?.automaticallyDownloadsUpdates = newValue
        }
    }

    func checkForUpdates() {
        lowerFloatingWindows()
        // A menu bar app is never frontmost on its own; bring Sparkle's window forward
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    // MARK: - Window levels

    /// Settings and AlwaysOn's other windows float so they stay above other apps,
    /// but Sparkle's update and progress windows are `.normal` and would open
    /// behind them. Lower ours while an update session shows its UI.
    /// (Sparkle's "up to date" and error alerts are modal, so they already show on top.)
    private func lowerFloatingWindows() {
        for window in NSApp.windows where window.level == .floating {
            window.level = .normal
            loweredWindows.add(window)
        }
    }

    private func restoreFloatingWindows() {
        for window in loweredWindows.allObjects {
            window.level = .floating
        }
        loweredWindows.removeAllObjects()
    }
}

// MARK: - SPUStandardUserDriverDelegate

extension AppUpdater: SPUStandardUserDriverDelegate {
    /// AlwaysOn lives in the menu bar, so a scheduled update alert would otherwise
    /// open behind whatever app is in front.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        lowerFloatingWindows()
        guard !state.userInitiated else { return }
        NSApp.activate(ignoringOtherApps: true)
    }

    func standardUserDriverWillFinishUpdateSession() {
        restoreFloatingWindows()
    }
}
