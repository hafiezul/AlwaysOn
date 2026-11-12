import Foundation
import Combine
import AppKit
import Carbon

/// Central state management for the AlwaysOn app
/// Keeps track of active status and coordinates with ActivitySimulator
@MainActor
final class AppState: NSObject, ObservableObject {
    /// The app's single state object, for entry points SwiftUI can't inject
    /// into, such as Shortcuts actions
    private(set) static weak var shared: AppState?

    // MARK: - Published Properties
    
    /// Whether the activity simulation is currently active
    @Published var isActive: Bool {
        didSet {
            UserDefaults.standard.set(isActive, forKey: Keys.isActive)
            // A start with no paused time is a new session; resuming isn't
            if isActive && !oldValue && pausedSessionDuration == 0 {
                telemetry.recordSessionStart(kind: SessionKind(sessionSource))
                menuAsks.noteSessionStarted()
            }
            // Resuming by any route makes a scheduled resume pointless
            if isActive { cancelAutoResume() }
            handleActiveStateChange()
        }
    }

    /// When a session paused with Pause for… resumes on its own; nil while
    /// running, stopped, or paused until resumed by hand. Kept in memory only.
    @Published private(set) var autoResumeAt: Date?
    
    /// Current activity interval in seconds
    @Published var activityInterval: TimeInterval {
        didSet {
            syncActiveProfileSettings()
            if isActive {
                // Restart simulator with new (possibly adjusted) interval
                restartActivitySimulatorWithCurrentSettings()
            }
        }
    }
    
    /// Current activity simulation method
    @Published var activityMethod: ActivityMethod {
        didSet {
            syncActiveProfileSettings()
            if isActive {
                activitySimulator.updateMethod(activityMethod)
            }
        }
    }
    
    /// Time since activation (for display purposes)
    @Published var activeSessionDuration: TimeInterval = 0
    
    /// Default timer duration setting
    @Published var defaultTimerDuration: QuickTimerDuration {
        didSet {
            syncActiveProfileSettings()
        }
    }

    /// Whether simulation is skipped while the user was recently active
    @Published var simulateOnlyWhenIdle: Bool {
        didSet {
            UserDefaults.standard.set(simulateOnlyWhenIdle, forKey: Keys.simulateOnlyWhenIdle)
            activitySimulator.gate.idleOnlyEnabled = simulateOnlyWhenIdle
        }
    }

    /// Whether simulation is skipped while no target app is running
    @Published var requireTargetApp: Bool {
        didSet {
            UserDefaults.standard.set(requireTargetApp, forKey: Keys.requireTargetApp)
            activitySimulator.gate.requireTargetApp = requireTargetApp
            runningAppMonitor.setEnabled(requireTargetApp)
        }
    }

    /// Whether simulation pauses while the screen is locked. Locking already
    /// shows most presence apps as Away, and input posted to the lock screen
    /// keeps waking the display, so this defaults to on.
    @Published var pauseWhileScreenLocked: Bool {
        didSet {
            UserDefaults.standard.set(pauseWhileScreenLocked, forKey: Keys.pauseWhileScreenLocked)
            applySystemConditions(systemEventMonitor.conditions)
        }
    }

    /// Stop a session after this long without input from the user
    @Published var awayLimit: AwayLimit {
        didSet {
            UserDefaults.standard.set(awayLimit.rawValue, forKey: Keys.awayLimit)
            activitySimulator.tracksRealInput = awayLimit != .off
        }
    }

    /// Stop a session when the battery reaches this level
    @Published var batteryStopThreshold: BatteryStopThreshold {
        didSet {
            UserDefaults.standard.set(batteryStopThreshold.rawValue, forKey: Keys.batteryStopThreshold)
            powerSourceMonitor.setEnabled(batteryStopThreshold != .off)
            if isActive, batteryStopThreshold.shouldStop(powerSourceMonitor.state) {
                performSafetyStop(.lowBattery(percent: powerSourceMonitor.state.percent ?? 0))
            }
        }
    }

    /// Why the last session ended on its own (timer, work hours, permission,
    /// safety stop), shown in the menu until the next session starts
    @Published var lastAutoStop: AutoStopEvent? {
        didSet {
            if let lastAutoStop, lastAutoStop != oldValue { telemetry.recordAutoStop(lastAutoStop.reason) }
        }
    }

    /// The usage statistics and GitHub star requests the menu may show
    @Published var menuAsks: MenuAsks {
        didSet {
            guard menuAsks != oldValue, let data = try? JSONEncoder().encode(menuAsks) else { return }
            UserDefaults.standard.set(data, forKey: Keys.menuAsks)
        }
    }

    /// Whether joining a Wi-Fi network listed on a profile switches to that profile
    @Published var switchProfilesByNetwork: Bool {
        didSet {
            UserDefaults.standard.set(switchProfilesByNetwork, forKey: Keys.switchProfilesByNetwork)
            wifiMonitor.setMonitoring(switchProfilesByNetwork)
            if switchProfilesByNetwork {
                if wifiMonitor.locationAccess == .notDetermined { wifiMonitor.requestLocationAccess() }
                handledNetwork = nil
                applyNetworkProfile()
            } else {
                pendingNetworkProfileId = nil
            }
        }
    }

    /// A network profile waiting for the current session to end
    @Published var pendingNetworkProfileId: UUID?

    /// The profile a Focus that ended will switch back to once the current
    /// session ends, for the menu; nil when no switch is waiting
    @Published var focusRestoreProfileName: String?

    /// The last automatic switch by network, shown in the menu until a session starts
    @Published var lastNetworkSwitch: NetworkSwitchEvent?

    /// What the menu bar item shows next to its icon
    @Published var menuBarLabelStyle: MenuBarLabelStyle {
        didSet {
            UserDefaults.standard.set(menuBarLabelStyle.rawValue, forKey: Keys.menuBarLabelStyle)
            rescheduleHeartbeat()
        }
    }

    /// Why simulation is suspended by the system (sleep, lock, user switch), nil while it may run.
    /// The session stays active; the simulator resumes as soon as the condition clears.
    @Published var systemSuspension: SystemConditions.SuspensionReason?

    /// Bundle IDs counted as target apps when requireTargetApp is on
    @Published var targetApps: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(targetApps), forKey: Keys.targetApps)
            activitySimulator.gate.targetBundleIDs = targetApps
        }
    }

    /// Apps the user added to the target list, beyond TargetApp.catalog
    @Published var customTargetApps: [TargetApp] {
        didSet {
            guard customTargetApps != oldValue, let data = try? JSONEncoder().encode(customTargetApps) else { return }
            UserDefaults.standard.set(data, forKey: Keys.customTargetApps)
        }
    }

    /// Whether the system-wide hotkey toggles the session
    @Published var globalHotKeyEnabled: Bool {
        didSet {
            UserDefaults.standard.set(globalHotKeyEnabled, forKey: Keys.globalHotKeyEnabled)
            refreshGlobalHotKey()
        }
    }

    /// The system-wide shortcut, ⌥⌘K unless the user records another
    @Published var globalHotKey: HotKey {
        didSet {
            if let data = try? JSONEncoder().encode(globalHotKey) {
                UserDefaults.standard.set(data, forKey: Keys.globalHotKey)
            }
            refreshGlobalHotKey()
        }
    }

    /// While Settings records a new shortcut, the current one is released so
    /// pressing it is recorded instead of toggling the session
    @Published var isRecordingHotKey = false {
        didSet { refreshGlobalHotKey() }
    }

    /// Whether macOS refused the shortcut, usually because another app owns it.
    /// Set only by refreshGlobalHotKey().
    @Published var isHotKeyUnavailable = false

    // MARK: - Pacing and Power

    /// Fixed-interval or adaptive pacing
    @Published var pulsePacing: PulsePacing {
        didSet {
            UserDefaults.standard.set(pulsePacing.rawValue, forKey: Keys.pulsePacing)
            if isActive { restartActivitySimulatorWithCurrentSettings() }
        }
    }

    /// Idle time after which adaptive pacing posts input
    @Published var adaptivePostAfter: AdaptivePostAfter {
        didSet {
            UserDefaults.standard.set(adaptivePostAfter.rawValue, forKey: Keys.adaptivePostAfter)
            activitySimulator.schedule = currentPulseSchedule
        }
    }

    /// Whether to stretch pacing while in Low Power Mode or running hot
    @Published var savesEnergyWhenConstrained: Bool {
        didSet {
            UserDefaults.standard.set(savesEnergyWhenConstrained, forKey: Keys.savesEnergyWhenConstrained)
            activitySimulator.schedule = currentPulseSchedule
        }
    }

    /// What stays awake during a session
    @Published var sleepPrevention: SleepPrevention {
        didSet {
            UserDefaults.standard.set(sleepPrevention.rawValue, forKey: Keys.sleepPrevention)
        }
    }

    /// Low Power Mode and thermal pressure, for pacing and display
    @Published var energyState: EnergyState

    /// Pacing for the simulator from the current settings and energy state
    var currentPulseSchedule: PulseSchedule {
        PulseSchedule(pacing: pulsePacing,
                      interval: activityInterval,
                      postAfter: PulseSchedule.postAfter(chosen: adaptivePostAfter,
                                                         screenSaverDelay: ScreenSaverSettings.idleDelay()),
                      savesEnergy: savesEnergyWhenConstrained && energyState.isConstrained)
    }
    
    // MARK: - Quick Timer Properties
    
    /// The end time for the quick timer (nil if no timer set)
    @Published var quickTimerEndTime: Date? {
        didSet {
            // Remember when this countdown began so the menu can show progress.
            // Moving an existing deadline (pause, resume, adding time) keeps the start.
            if quickTimerEndTime == nil {
                timerStartedAt = nil
            } else if oldValue == nil {
                timerStartedAt = Date()
            }
            if let endTime = quickTimerEndTime {
                UserDefaults.standard.set(endTime, forKey: Keys.quickTimerEndTime)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.quickTimerEndTime)
            }
            // Show the new countdown at once; the next tick may be up to a minute away
            quickTimerRemaining = max(0, quickTimerEndTime?.timeIntervalSinceNow ?? 0)
            rescheduleHeartbeat()
        }
    }
    
    /// Remaining time on the quick timer
    @Published var quickTimerRemaining: TimeInterval = 0

    /// When the current countdown began, for the menu's progress ring
    private(set) var timerStartedAt: Date? {
        didSet {
            if let timerStartedAt {
                UserDefaults.standard.set(timerStartedAt, forKey: Keys.timerStartedAt)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.timerStartedAt)
            }
        }
    }

    /// How far through its countdown the session is, 0...1, nil without a deadline
    var sessionProgress: Double? {
        guard let deadline = sessionDeadline else { return nil }
        let start = timerStartedAt ?? deadline.addingTimeInterval(-max(quickTimerRemaining, 1))
        let total = deadline.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(max(1 - quickTimerRemaining / total, 0), 1)
    }
    
    /// Whether a quick timer is currently active
    var isQuickTimerActive: Bool {
        quickTimerEndTime != nil && isActive
    }
    
    // MARK: - Permission Management
    
    /// Accessibility permission state. macOS offers no change callback, so it is
    /// re-checked when it matters: menu open, app activation, session starts,
    /// each simulation tick, and fast polling only while the user is granting it.
    let accessibilityPermission = AccessibilityPermission.shared
    
    /// Convenience accessor for permission state
    var hasAccessibilityPermission: Bool {
        accessibilityPermission.hasPermission
    }
    
    // MARK: - Automation
    
    /// Work schedule manager for auto-enable/disable during work hours
    let workScheduleManager: WorkScheduleManager

    /// Named profile manager for profile-scoped settings
    let profileManager: ProfileManager
    
    /// Notification manager for work schedule events
    let notificationManager = NotificationManager()

    /// Opt-in anonymous usage statistics
    let telemetry = TelemetryClient.shared

    /// Daily online time, kept on this Mac for 30 days
    let activityHistory = ActivityHistoryStore()

    /// Current Wi-Fi network and the Location permission needed to read it
    let wifiMonitor = WiFiNetworkMonitor()

    /// The network whose profile rule already ran, so a manual profile choice
    /// sticks until the Mac joins a different network
    var handledNetwork: String?

    /// How the current or paused session was started
    /// Persisted so a relaunched schedule-started session can still be stopped by schedule end
    @Published var sessionSource: SessionSource? {
        didSet {
            if let source = sessionSource,
               let data = try? JSONEncoder().encode(source) {
                UserDefaults.standard.set(data, forKey: Keys.sessionSource)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.sessionSource)
            }
        }
    }
    
    // MARK: - Services and Session Bookkeeping
    // Internal rather than private so the AppState+*.swift extensions can reach them.
    
    let activitySimulator = ActivitySimulator()
    var pulseLog: PulseLog { activitySimulator.pulseLog }
    let globalHotKeyManager = GlobalHotKeyManager()
    let systemEventMonitor = SystemEventMonitor()
    let runningAppMonitor = RunningAppMonitor()
    let powerSourceMonitor = PowerSourceMonitor()
    let energyMonitor = EnergyMonitor()
    let powerAssertions = PowerAssertionManager()
    private var sessionTimer: Timer?
    private var autoResumeTimer: Timer?

    /// Whether the menu is on screen. Only the open menu shows seconds, so the
    /// heartbeat runs every second only while this is true.
    var isMenuVisible = false {
        didSet {
            guard isMenuVisible != oldValue else { return }
            if isMenuVisible {
                accessibilityPermission.refresh()
                tickSessionState()
                refreshFocusFilter()
            }
            rescheduleHeartbeat()
        }
    }
    private var sessionStartTime: Date?
    var cancellables = Set<AnyCancellable>()
    
    /// Accumulated session duration when paused (for pause/resume functionality)
    private var pausedSessionDuration: TimeInterval = 0
    
    /// Saved quick timer end time when paused (for pause/resume functionality)
    private var pausedQuickTimerEndTime: Date?
    
    /// Prevent profile application from rewriting the active profile recursively
    var isApplyingProfile = false

    /// Keep profile switches inactive even if the new schedule is currently active
    var suppressScheduleAutoStart = false
    
    // MARK: - Constants
    
    enum Keys {
        static let isActive = "isActive"
        static let activityInterval = "activityInterval"
        static let activityMethod = "activityMethod"
        static let quickTimerEndTime = "quickTimerEndTime"
        static let defaultTimerDuration = "defaultTimerDuration"
        static let sessionSource = "sessionSource"
        static let simulateOnlyWhenIdle = "simulateOnlyWhenIdle"
        static let requireTargetApp = "requireTargetApp"
        static let targetApps = "targetApps"
        static let customTargetApps = "customTargetApps"
        static let globalHotKeyEnabled = "globalHotKeyEnabled"
        static let globalHotKey = "globalHotKey"
        static let pauseWhileScreenLocked = "pauseWhileScreenLocked"
        static let awayLimit = "awayLimitHours"
        static let batteryStopThreshold = "batteryStopThreshold"
        static let timerStartedAt = "quickTimerStartedAt"
        static let menuBarLabelStyle = "menuBarLabelStyle"
        static let switchProfilesByNetwork = "switchProfilesByNetwork"
        static let pulsePacing = "pulsePacing"
        static let adaptivePostAfter = "adaptivePostAfterSeconds"
        static let savesEnergyWhenConstrained = "savesEnergyWhenConstrained"
        static let sleepPrevention = "sleepPrevention"
        static let menuAsks = "menuAsks"
    }
    
    enum Defaults {
        static let activityInterval: TimeInterval = 45.0
        static let activityMethod: ActivityMethod = .mouse
        static let defaultTimerDuration: QuickTimerDuration = .noLimit
    }
    
    // MARK: - Onboarding State
    
    /// Whether to show the permissions window on launch
    var needsPermissionsOnboarding: Bool {
        !accessibilityPermission.onboardingCompleted || !accessibilityPermission.hasPermission
    }
    
    // MARK: - Computed Properties

    var sessionSourceLabel: String? {
        guard let source = sessionSource else { return nil }

        switch source {
        case .manual:
            return nil
        case .quickTimer:
            return "via Quick Timer"
        case .until(_, let label):
            return label.map { "Until · \($0)" } ?? "Until time"
        case .command:
            return "via Command"
        case .focus:
            return "via Focus"
        case .workSchedule(let name):
            return name.isEmpty ? "via Work Schedule" : "via Work Schedule · \(name)"
        }
    }

    var sessionEndCondition: SessionEndCondition {
        sessionSource?.endCondition(quickTimerDeadline: quickTimerEndTime) ??
            quickTimerEndTime.map { .deadline($0) } ?? .unlimited
    }

    var sessionDeadline: Date? { sessionEndCondition.deadline }

    var hasActiveOrPausedSession: Bool {
        isActive || sessionSource != nil || pausedSessionDuration > 0 || activeSessionDuration > 0
    }

    var isScheduleControlledSession: Bool {
        guard case .workSchedule = sessionSource else { return false }
        return true
    }
    
    // MARK: - Initialization
    
    override init() {
        let defaults = UserDefaults.standard
        ProfileManager.migrateIfNeeded(defaults: defaults)

        let profileManager = ProfileManager(defaults: defaults)
        let initialProfile = profileManager.activeProfile ?? Profile.makeDefault(from: defaults)

        self.profileManager = profileManager
        self.workScheduleManager = WorkScheduleManager(schedule: initialProfile.workSchedule)

        // Restore persisted state through backing storage so the didSet side
        // effects (persistence writes, simulator restarts, simulation starts)
        // don't re-run before initialization finishes
        self._isActive = Published(initialValue: defaults.bool(forKey: Keys.isActive))
        self._activityInterval = Published(initialValue: initialProfile.activityInterval > 0 ? initialProfile.activityInterval : Defaults.activityInterval)
        self._activityMethod = Published(initialValue: initialProfile.activityMethod)
        self._defaultTimerDuration = Published(initialValue: initialProfile.defaultTimerDuration)
        self._simulateOnlyWhenIdle = Published(initialValue: defaults.bool(forKey: Keys.simulateOnlyWhenIdle))
        self._requireTargetApp = Published(initialValue: defaults.bool(forKey: Keys.requireTargetApp))
        self._targetApps = Published(initialValue: Set(defaults.stringArray(forKey: Keys.targetApps) ?? []))
        self._customTargetApps = Published(initialValue: defaults.data(forKey: Keys.customTargetApps)
            .flatMap { try? JSONDecoder().decode([TargetApp].self, from: $0) } ?? [])
        self._globalHotKeyEnabled = Published(initialValue: defaults.object(forKey: Keys.globalHotKeyEnabled) as? Bool ?? true)
        self._globalHotKey = Published(initialValue: defaults.data(forKey: Keys.globalHotKey)
            .flatMap { try? JSONDecoder().decode(HotKey.self, from: $0) } ?? .default)
        self._pauseWhileScreenLocked = Published(initialValue: defaults.object(forKey: Keys.pauseWhileScreenLocked) as? Bool ?? true)
        self._awayLimit = Published(initialValue: AwayLimit(rawValue: defaults.integer(forKey: Keys.awayLimit)) ?? .off)
        self._batteryStopThreshold = Published(initialValue: BatteryStopThreshold(rawValue: defaults.integer(forKey: Keys.batteryStopThreshold)) ?? .off)
        self._switchProfilesByNetwork = Published(initialValue: defaults.bool(forKey: Keys.switchProfilesByNetwork))
        self._menuBarLabelStyle = Published(initialValue: MenuBarLabelStyle(rawValue: defaults.string(forKey: Keys.menuBarLabelStyle) ?? "") ?? .iconAndTime)
        self._pulsePacing = Published(initialValue: PulsePacing(rawValue: defaults.string(forKey: Keys.pulsePacing) ?? "") ?? .fixed)
        self._adaptivePostAfter = Published(initialValue: AdaptivePostAfter(rawValue: defaults.integer(forKey: Keys.adaptivePostAfter)) ?? .twoMinutes)
        self._savesEnergyWhenConstrained = Published(initialValue: defaults.object(forKey: Keys.savesEnergyWhenConstrained) as? Bool ?? true)
        self._sleepPrevention = Published(initialValue: SleepPrevention(rawValue: defaults.string(forKey: Keys.sleepPrevention) ?? "") ?? .off)
        self._energyState = Published(initialValue: EnergyMonitor.readState())
        self._menuAsks = Published(initialValue: defaults.data(forKey: Keys.menuAsks)
            .flatMap { try? JSONDecoder().decode(MenuAsks.self, from: $0) } ?? MenuAsks())
        super.init()
        Self.shared = self
        menuAsks.noteLaunch(now: Date())
        activitySimulator.gate.idleOnlyEnabled = simulateOnlyWhenIdle
        activitySimulator.gate.requireTargetApp = requireTargetApp
        activitySimulator.gate.targetBundleIDs = targetApps
        runningAppMonitor.setEnabled(requireTargetApp)
        activitySimulator.hasRunningTargetProvider = { [runningAppMonitor] bundleIDs in
            runningAppMonitor.isAnyRunning(bundleIDs)
        }
        activitySimulator.onPermissionLost = { [weak self] in
            Task { @MainActor in self?.accessibilityPermission.refresh() }
        }
        activitySimulator.onInputFailed = { [weak self] in
            Task { @MainActor in self?.telemetry.recordInputFailure() }
        }
        systemSuspension = systemEventMonitor.conditions.suspensionReason(pauseWhileLocked: pauseWhileScreenLocked)
        activitySimulator.tracksRealInput = awayLimit != .off
        activitySimulator.shouldContinue = { [weak self] awayFor in
            MainActor.assumeIsolated { self?.continueAfterSafetyCheck(awayFor: awayFor) ?? true }
        }
        powerSourceMonitor.onChange = { [weak self] state in
            MainActor.assumeIsolated { self?.handleBatteryChange(state) }
        }
        powerSourceMonitor.setEnabled(batteryStopThreshold != .off)
        wifiMonitor.onNetworkChange = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.handledNetwork = nil
                self.applyNetworkProfile()
            }
        }
        globalHotKeyManager.onKeyDown = { [weak self] in
            Task { @MainActor in
                self?.toggle()
            }
        }
        refreshGlobalHotKey()
        
        let savedEndTime = defaults.object(forKey: Keys.quickTimerEndTime) as? Date
        let sourceData = defaults.data(forKey: Keys.sessionSource)
        let restoredSource = sourceData.flatMap { try? JSONDecoder().decode(SessionSource.self, from: $0) }
        let now = Date()
        let expiredTimer = savedEndTime.map { SessionEndCondition.deadline($0).hasExpired(at: now) } ?? false
        let shouldRestore = restoredSource.map {
            $0.canRestore(isActive: isActive, quickTimerDeadline: savedEndTime, now: now)
        } ?? (isActive && sourceData == nil)
        if shouldRestore && !expiredTimer {
            self._quickTimerEndTime = Published(initialValue: savedEndTime)
            self.timerStartedAt = savedEndTime == nil ? nil : defaults.object(forKey: Keys.timerStartedAt) as? Date
            self._sessionSource = Published(initialValue: restoredSource)
            self._quickTimerRemaining = Published(initialValue: max(0, sessionDeadline?.timeIntervalSince(now) ?? 0))
        } else {
            stopSession()
        }

        // Set up Combine subscriptions
        setupPermissionObserver()
        setupAutomationObservers()
        setupNestedObjectChangeForwarding()
        setupNotificationCallbacks()
        setupProfileSync()
        setupSystemEventHandling()
        setupActivityHistory()
        setupNetworkProfiles()
        setupPacingAndPower()
        setupFocusRestore()
        setupTelemetry()
        accessibilityPermission.refresh()
        // Pick up a Focus that is already on, or one that ended while AlwaysOn was closed
        refreshFocusFilter(onlyIfFocusOwnsSomething: false)
        
        // Resume active state if was active before quit (and has permission)
        if isActive && hasAccessibilityPermission {
            startActivitySimulation()
        } else if isActive && !hasAccessibilityPermission {
            // Reset active state if permissions are missing
            isActive = false
        } else if sessionSource?.chosenEndDate != nil {
            rescheduleHeartbeat()
        }
    }
    
    // MARK: - Target Apps

    /// Adds the app at `url` to the target list and selects it.
    /// - Returns: false when `url` isn't a readable app, or is AlwaysOn itself
    @discardableResult
    func addTargetApp(at url: URL) -> Bool {
        guard let app = TargetApp.custom(fromAppAt: url), app.bundleID != TargetApp.ownBundleID else { return false }
        customTargetApps = TargetApp.adding(app, to: customTargetApps)
        targetApps.insert(app.bundleID)
        return true
    }

    /// Removes an app the user added, and deselects it
    func removeCustomTargetApp(_ app: TargetApp) {
        customTargetApps.removeAll { $0.bundleID == app.bundleID }
        targetApps.remove(app.bundleID)
    }

    // MARK: - Public Methods
    
    /// Toggle the active state (pause/resume)
    func toggle() {
        if !isActive { accessibilityPermission.refresh() }
        if !isActive && !hasAccessibilityPermission {
            // Request permission and wait for it
            accessibilityPermission.request()
            return
        }
        
        if expireSessionIfNeeded() { return }
        sessionSource = sessionSource?.relinquishingCommand
        if isActive {
            // PAUSING - Save current session state. The display value only
            // updates while the menu is open, so read the clock directly.
            refreshElapsedTime()
            pausedSessionDuration = activeSessionDuration
            pausedQuickTimerEndTime = quickTimerEndTime
        } else {
            switch sessionSource {
            case .until: break
            default: sessionSource = .manual
            }
            
            // Restore quick timer if it was active when paused
            if let absoluteDeadline = sessionSource?.endCondition(quickTimerDeadline: nil).deadline {
                quickTimerEndTime = absoluteDeadline
            } else if let savedTimerEndTime = pausedQuickTimerEndTime {
                quickTimerEndTime = savedTimerEndTime
            } else {
                // No saved timer, apply default timer if set
                if let seconds = defaultTimerDuration.seconds {
                    quickTimerEndTime = Date().addingTimeInterval(seconds)
                } else {
                    quickTimerEndTime = nil
                }
            }
            
        }
        
        isActive.toggle()
    }
    
    /// Pauses a running session, and resumes it on its own after `seconds`
    /// when given. A session's end time still applies while paused.
    func pause(for seconds: TimeInterval?) {
        guard isActive else { return }
        toggle()
        // toggle() stops instead of pausing a session whose end time has passed
        guard !isActive, hasActiveOrPausedSession, let seconds, seconds > 0 else { return }
        let resumeAt = Date().addingTimeInterval(seconds)
        autoResumeAt = resumeAt
        let timer = Timer(fire: resumeAt, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.resumeIfDue() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        autoResumeTimer = timer
    }

    /// Resumes a paused session whose Pause for… time has passed. Also runs
    /// after wake, since timers don't fire while the Mac sleeps.
    func resumeIfDue() {
        guard let resumeAt = autoResumeAt, resumeAt <= Date() else { return }
        cancelAutoResume()
        guard !isActive, hasActiveOrPausedSession else { return }
        let owner = sessionSource
        toggle()
        // Resuming by hand hands the session to the user; resuming on its own
        // doesn't, so work hours or a Focus can still end it
        guard isActive else { return }
        switch owner {
        case .workSchedule?, .focus?, .quickTimer?: sessionSource = owner
        default: break
        }
    }

    private func cancelAutoResume() {
        autoResumeTimer?.invalidate()
        autoResumeTimer = nil
        autoResumeAt = nil
    }

    /// Stop session completely (full reset)
    func stopSession() {
        cancelAutoResume()
        sessionSource = nil
        
        // Clear all session state
        pausedSessionDuration = 0
        pausedQuickTimerEndTime = nil
        quickTimerEndTime = nil
        quickTimerRemaining = 0
        // Clear the start time first so stopping can't recompute a duration
        sessionStartTime = nil
        activeSessionDuration = 0
        isActive = false
    }

    /// Start with a quick timer duration
    func startWithQuickTimer(_ duration: QuickTimerDuration) {
        accessibilityPermission.refresh()
        if !hasAccessibilityPermission {
            accessibilityPermission.request()
            return
        }

        stopSession()
        sessionSource = .quickTimer
        
        if let seconds = duration.seconds {
            quickTimerEndTime = Date().addingTimeInterval(seconds)
        } else {
            quickTimerEndTime = nil
        }
        
        if !isActive {
            isActive = true
        }
    }
    
    @discardableResult
    func startUntil(date: Date, label: String? = nil) -> Bool {
        accessibilityPermission.refresh()
        guard let source = SessionSource.validatedUntil(date: date, label: label, now: Date(),
                                                       hasPermission: hasAccessibilityPermission) else { return false }
        replaceSession(source: source)
        return true
    }

    func replaceSession(source: SessionSource) {
        stopSession()
        sessionSource = source
        quickTimerEndTime = source.endCondition(quickTimerDeadline: nil).deadline
        quickTimerRemaining = max(0, quickTimerEndTime?.timeIntervalSinceNow ?? 0)
        isActive = true
    }

    /// Cancel the quick timer but keep activity running
    func cancelQuickTimer() {
        sessionSource = sessionSource?.cancellingCountdown
        pausedQuickTimerEndTime = nil
        quickTimerEndTime = nil
        activitySimulator.deadline = nil
        quickTimerRemaining = 0
        rescheduleHeartbeat()
    }
    
    /// Adds time to the session: a session with an end ends later, an
    /// unlimited one gains an end. Works while paused too.
    func addTime(_ seconds: TimeInterval) {
        guard hasActiveOrPausedSession, seconds > 0 else { return }
        let change = (sessionSource ?? .manual).addingTime(seconds, quickTimerDeadline: quickTimerEndTime, now: Date())
        sessionSource = change.source
        // A paused session resumes to its saved deadline, so move that too
        if !isActive { pausedQuickTimerEndTime = change.deadline }
        quickTimerEndTime = change.deadline
        activitySimulator.deadline = change.deadline
    }

    func restartActivitySimulatorWithCurrentSettings() {
        guard !expireSessionIfNeeded() else { return }
        activitySimulator.stop()
        startSimulatorUnlessSuspended()
    }

    /// Starts the simulator for the current session unless the system has suspended it
    func startSimulatorUnlessSuspended() {
        guard systemSuspension == nil else { return }
        activitySimulator.deadline = sessionDeadline
        activitySimulator.start(schedule: currentPulseSchedule, method: activityMethod)
    }

    /// One line describing the session, for Shortcuts and accessibility
    var statusSummary: String {
        if isActive {
            if let deadline = sessionDeadline {
                return "AlwaysOn is active until \(deadline.formatted(date: .omitted, time: .shortened))."
            }
            return "AlwaysOn is active."
        }
        if let autoResumeAt, hasActiveOrPausedSession {
            return "AlwaysOn is paused until \(autoResumeAt.formatted(date: .omitted, time: .shortened))."
        }
        return hasActiveOrPausedSession ? "AlwaysOn is paused." : "AlwaysOn is off."
    }

    func handleActiveStateChange() {
        if isActive {
            startActivitySimulation()
        } else {
            stopActivitySimulation()
        }
    }
    
    func startActivitySimulation() {
        guard !expireSessionIfNeeded() else { return }
        guard hasAccessibilityPermission else {
            isActive = false
            return
        }
        if batteryStopThreshold.shouldStop(powerSourceMonitor.state) {
            performSafetyStop(.lowBattery(percent: powerSourceMonitor.state.percent ?? 0))
            return
        }
        lastAutoStop = nil
        lastNetworkSwitch = nil
        
        startSimulatorUnlessSuspended()
        
        // Set session start time accounting for paused duration
        if pausedSessionDuration > 0 {
            // Resuming: Calculate start time to continue from paused duration
            sessionStartTime = Date().addingTimeInterval(-pausedSessionDuration)
        } else {
            // New session: Start from now
            sessionStartTime = Date()
        }
        
        rescheduleHeartbeat()
    }
    
    func stopActivitySimulation() {
        activitySimulator.stop()
        
        // Freeze the displayed duration for pause/resume, then stop counting.
        // The pausedSessionDuration is set in toggle() before stopping.
        refreshElapsedTime()
        sessionStartTime = nil

        // A paused session with a deadline still needs to expire on time
        rescheduleHeartbeat()
        
        // Keep activeSessionDuration as-is for display while paused
        // Don't reset quickTimerRemaining - it will be calculated on resume
    }
    
    /// One heartbeat drives both the on-screen times and deadline expiry.
    /// HeartbeatPlanner picks the next moment anything visible or due changes:
    /// every second while the menu is open or in the final minute, at minute
    /// label changes otherwise, and never for an unlimited session with the
    /// menu closed. Any previous heartbeat is invalidated first, so repeated
    /// paths (launch restore, deadline edits) can't stack timers.
    func rescheduleHeartbeat() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        guard isActive || sessionDeadline != nil,
              let delay = HeartbeatPlanner.nextTickDelay(now: Date(), deadline: sessionDeadline,
                                                        isRunning: isActive, isMenuVisible: isMenuVisible,
                                                        showsMenuBarCountdown: menuBarLabelStyle == .iconAndTime)
        else { return }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tickSessionState()
                self.rescheduleHeartbeat()
            }
        }
        timer.tolerance = HeartbeatPlanner.tolerance(for: delay)
        RunLoop.main.add(timer, forMode: .common)
        sessionTimer = timer
    }

    /// Brings the displayed session duration up to date with the clock
    func refreshElapsedTime() {
        if let startTime = sessionStartTime {
            activeSessionDuration = Date().timeIntervalSince(startTime)
        }
    }
    
    func tickSessionState() {
        refreshElapsedTime()
        
        if expireSessionIfNeeded() { return }
        if let endTime = sessionDeadline {
            quickTimerRemaining = max(0, endTime.timeIntervalSinceNow)
        }
    }

    @discardableResult
    func expireSessionIfNeeded() -> Bool {
        guard sessionEndCondition.hasExpired(at: Date()) else { return false }
        stopSession()
        lastAutoStop = AutoStopEvent(reason: .timerEnded, date: Date())
        if workScheduleManager.schedule.isEnabled && workScheduleManager.isWithinSchedule {
            notificationManager.notifyQuickTimerExpired()
        }
        return true
    }
}
