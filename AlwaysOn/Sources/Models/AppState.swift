import Foundation
import Combine
import AppKit
import Carbon

/// Central state management for the AlwaysOn app
/// Keeps track of active status and coordinates with ActivitySimulator
@MainActor
final class AppState: NSObject, ObservableObject {
    // MARK: - Published Properties
    
    /// Whether the activity simulation is currently active
    @Published var isActive: Bool {
        didSet {
            UserDefaults.standard.set(isActive, forKey: Keys.isActive)
            handleActiveStateChange()
        }
    }
    
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

    /// Why simulation is suspended by the system (sleep, lock, user switch), nil while it may run.
    /// The session stays active; the simulator resumes as soon as the condition clears.
    @Published private(set) var systemSuspension: SystemConditions.SuspensionReason?

    /// Bundle IDs counted as target apps when requireTargetApp is on
    @Published var targetApps: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(targetApps), forKey: Keys.targetApps)
            activitySimulator.gate.targetBundleIDs = targetApps
        }
    }

    /// Whether the system-wide ⌥⌘K hotkey toggles the session
    @Published var globalHotKeyEnabled: Bool {
        didSet {
            UserDefaults.standard.set(globalHotKeyEnabled, forKey: Keys.globalHotKeyEnabled)
            refreshGlobalHotKey()
        }
    }
    
    // MARK: - Quick Timer Properties
    
    /// The end time for the quick timer (nil if no timer set)
    @Published var quickTimerEndTime: Date? {
        didSet {
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

    /// How the current or paused session was started
    /// Persisted so a relaunched schedule-started session can still be stopped by schedule end
    @Published private(set) var sessionSource: SessionSource? {
        didSet {
            if let source = sessionSource,
               let data = try? JSONEncoder().encode(source) {
                UserDefaults.standard.set(data, forKey: Keys.sessionSource)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.sessionSource)
            }
        }
    }
    
    // MARK: - Private Properties
    
    private let activitySimulator = ActivitySimulator()
    var pulseLog: PulseLog { activitySimulator.pulseLog }
    private let globalHotKeyManager = GlobalHotKeyManager()
    private let systemEventMonitor = SystemEventMonitor()
    private let runningAppMonitor = RunningAppMonitor()
    private var sessionTimer: Timer?

    /// Whether the menu is on screen. Only the open menu shows seconds, so the
    /// heartbeat runs every second only while this is true.
    var isMenuVisible = false {
        didSet {
            guard isMenuVisible != oldValue else { return }
            if isMenuVisible {
                accessibilityPermission.refresh()
                tickSessionState()
            }
            rescheduleHeartbeat()
        }
    }
    private var sessionStartTime: Date?
    private var cancellables = Set<AnyCancellable>()
    
    /// Accumulated session duration when paused (for pause/resume functionality)
    private var pausedSessionDuration: TimeInterval = 0
    
    /// Saved quick timer end time when paused (for pause/resume functionality)
    private var pausedQuickTimerEndTime: Date?
    
    /// Prevent profile application from rewriting the active profile recursively
    private var isApplyingProfile = false

    /// Keep profile switches inactive even if the new schedule is currently active
    private var suppressScheduleAutoStart = false
    
    // MARK: - Constants
    
    private enum Keys {
        static let isActive = "isActive"
        static let activityInterval = "activityInterval"
        static let activityMethod = "activityMethod"
        static let quickTimerEndTime = "quickTimerEndTime"
        static let defaultTimerDuration = "defaultTimerDuration"
        static let sessionSource = "sessionSource"
        static let simulateOnlyWhenIdle = "simulateOnlyWhenIdle"
        static let requireTargetApp = "requireTargetApp"
        static let targetApps = "targetApps"
        static let globalHotKeyEnabled = "globalHotKeyEnabled"
        static let pauseWhileScreenLocked = "pauseWhileScreenLocked"
    }
    
    private enum Defaults {
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

    private var isScheduleControlledSession: Bool {
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
        self._globalHotKeyEnabled = Published(initialValue: defaults.object(forKey: Keys.globalHotKeyEnabled) as? Bool ?? true)
        self._pauseWhileScreenLocked = Published(initialValue: defaults.object(forKey: Keys.pauseWhileScreenLocked) as? Bool ?? true)
        super.init()
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
        systemSuspension = systemEventMonitor.conditions.suspensionReason(pauseWhileLocked: pauseWhileScreenLocked)
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
        accessibilityPermission.refresh()
        
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
    
    /// Stop session completely (full reset)
    func stopSession() {
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

    func applyProfile(_ profile: Profile) {
        stopSession()
        isApplyingProfile = true
        suppressScheduleAutoStart = true
        defer {
            isApplyingProfile = false
            suppressScheduleAutoStart = false
        }

        activityInterval = profile.activityInterval > 0 ? profile.activityInterval : Defaults.activityInterval
        activityMethod = profile.activityMethod
        defaultTimerDuration = profile.defaultTimerDuration
        workScheduleManager.schedule = profile.workSchedule
        quickTimerEndTime = nil
        quickTimerRemaining = 0
    }

    func switchProfile(_ id: UUID) {
        guard id != profileManager.activeProfileId else { return }

        syncActiveProfileSettings()
        let wasActive = isActive || activeSessionDuration > 0

        // Priority: Manual user action > Profile switch > Work Schedule
        stopSession()

        guard let newProfile = profileManager.switchProfile(to: id) else { return }
        applyProfile(newProfile)

        if wasActive {
            notificationManager.notifyProfileSwitchedDuringSession(newProfileName: newProfile.name)
        }
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

    private func replaceSession(source: SessionSource) {
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
    
    /// Request permission with system prompt
    func requestPermission() {
        accessibilityPermission.request()
    }
    
    /// Open System Preferences to grant accessibility permission
    func openAccessibilitySettings() {
        accessibilityPermission.openSettings()
    }
    
    /// Show the permissions window
    func showPermissionsWindow() {
        PermissionsWindowController.shared.show(
            accessibilityPermission: accessibilityPermission,
            onContinue: { [weak self] in
                guard let self else { return }
                self.accessibilityPermission.onboardingCompleted = true
                // The prompt is done; later checks happen on demand
                self.accessibilityPermission.stopPolling()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )
    }

    /// Complete the permission setup (called after onboarding)
    func completePermissionSetup() {
        accessibilityPermission.onboardingCompleted = true
        // Onboarding is done; later checks happen on demand
        accessibilityPermission.stopPolling()
    }
    
    // MARK: - Private Methods
    
    private func setupPermissionObserver() {
        // React to permission state changes
        accessibilityPermission.$hasPermission
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (hasPermission: Bool) in
                guard let self else { return }
                
                // If permission was revoked while active, stop simulation
                if !hasPermission && self.isActive {
                    self.isActive = false
                }
            }
            .store(in: &cancellables)
    }
    
    /// Forward nested ObservableObject changes to trigger SwiftUI view updates
    private func setupNestedObjectChangeForwarding() {
        // When nested ObservableObjects change, SwiftUI doesn't automatically detect it
        // because it only observes one level deep. We need to manually forward changes.
        
        accessibilityPermission.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: Void) in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        profileManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: Void) in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        notificationManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: Void) in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    private func setupAutomationObservers() {
        // Work Schedule: Auto-enable/disable based on schedule
        workScheduleManager.onScheduleStateChanged = { [weak self] (isWithinSchedule: Bool) in
            guard let self else { return }
            Task { @MainActor in
                self.handleWorkScheduleChange(isWithinSchedule: isWithinSchedule)
            }
        }
    }
    
    private func setupNotificationCallbacks() {
        // Handle quick timer resume action from notification
        notificationManager.onQuickTimerResumeTapped = { [weak self] in
            guard let self else { return }
            // Resume activity if not already active
            self.accessibilityPermission.refresh()
            if !self.isActive && self.hasAccessibilityPermission {
                self.stopSession()
                self.sessionSource = .manual
                self.isActive = true
            }
        }
    }

    private func setupProfileSync() {
        workScheduleManager.$schedule
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: WorkSchedule) in
                self?.syncActiveProfileSettings()
            }
            .store(in: &cancellables)
    }

    private func syncActiveProfileSettings() {
        guard !isApplyingProfile else { return }
        profileManager.updateProfileSettings(
            profileManager.activeProfileId,
            activityInterval: activityInterval,
            activityMethod: activityMethod,
            defaultTimerDuration: defaultTimerDuration,
            workSchedule: workScheduleManager.schedule
        )
    }
    
    // MARK: - Automation Handlers
    
    private func handleWorkScheduleChange(isWithinSchedule: Bool) {
        guard workScheduleManager.schedule.isEnabled else { return }
        
        if isWithinSchedule {
            guard !suppressScheduleAutoStart else { return }
            
            // Auto-enable only when there is no active or paused session to preserve manual control.
            accessibilityPermission.refresh()
            if !hasActiveOrPausedSession && hasAccessibilityPermission {
                stopSession()
                sessionSource = .workSchedule(profileName: profileManager.activeProfile?.name ?? "")
                isActive = true
                notificationManager.notifyWorkScheduleStarted()
            }
        } else {
            guard isScheduleControlledSession && hasActiveOrPausedSession else { return }
            
            stopSession()
            notificationManager.notifyWorkScheduleEnded()
        }
    }
    
    private func restartActivitySimulatorWithCurrentSettings() {
        guard !expireSessionIfNeeded() else { return }
        activitySimulator.stop()
        startSimulatorUnlessSuspended()
    }

    /// Starts the simulator for the current session unless the system has suspended it
    private func startSimulatorUnlessSuspended() {
        guard systemSuspension == nil else { return }
        activitySimulator.deadline = sessionDeadline
        activitySimulator.start(interval: activityInterval, method: activityMethod)
    }

    // MARK: - System Events

    private func setupSystemEventHandling() {
        systemEventMonitor.onConditionsChanged = { [weak self] conditions in
            MainActor.assumeIsolated { self?.applySystemConditions(conditions) }
        }
        systemEventMonitor.onClockMayHaveJumped = { [weak self] in
            MainActor.assumeIsolated { self?.handleClockMayHaveJumped() }
        }
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.accessibilityPermission.refresh() }
            .store(in: &cancellables)
    }

    /// Suspends the simulator while the Mac sleeps, locks, or switches users,
    /// and resumes it, with an immediate tick, once the condition clears
    private func applySystemConditions(_ conditions: SystemConditions) {
        let reason = conditions.suspensionReason(pauseWhileLocked: pauseWhileScreenLocked)
        guard reason != systemSuspension else { return }
        systemSuspension = reason
        guard isActive else { return }
        if reason != nil {
            activitySimulator.stop()
            pulseLog.record(.systemPaused)
        } else {
            restartActivitySimulatorWithCurrentSettings()
        }
    }

    /// Timers don't run during sleep and don't follow wall-clock jumps, so
    /// re-check deadlines, the schedule, and permission straight away
    private func handleClockMayHaveJumped() {
        accessibilityPermission.refresh()
        expireSessionIfNeeded()
        workScheduleManager.checkNow()
        tickSessionState()
        rescheduleHeartbeat()
    }

    private func refreshGlobalHotKey() {
        if globalHotKeyEnabled {
            globalHotKeyManager.register(keyCode: UInt32(kVK_ANSI_K),
                                         modifiers: UInt32(optionKey | cmdKey))
        } else {
            globalHotKeyManager.unregister()
        }
    }
    
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
        }
    }
    
    private func handleActiveStateChange() {
        if isActive {
            startActivitySimulation()
        } else {
            stopActivitySimulation()
        }
    }
    
    private func startActivitySimulation() {
        guard !expireSessionIfNeeded() else { return }
        guard hasAccessibilityPermission else {
            isActive = false
            return
        }
        
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
    
    private func stopActivitySimulation() {
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
    private func rescheduleHeartbeat() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        guard isActive || sessionDeadline != nil,
              let delay = HeartbeatPlanner.nextTickDelay(now: Date(), deadline: sessionDeadline,
                                                        isRunning: isActive, isMenuVisible: isMenuVisible)
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
    private func refreshElapsedTime() {
        if let startTime = sessionStartTime {
            activeSessionDuration = Date().timeIntervalSince(startTime)
        }
    }
    
    private func tickSessionState() {
        refreshElapsedTime()
        
        if expireSessionIfNeeded() { return }
        if let endTime = sessionDeadline {
            quickTimerRemaining = max(0, endTime.timeIntervalSinceNow)
        }
    }

    @discardableResult
    private func expireSessionIfNeeded() -> Bool {
        guard sessionEndCondition.hasExpired(at: Date()) else { return false }
        stopSession()
        if workScheduleManager.schedule.isEnabled && workScheduleManager.isWithinSchedule {
            notificationManager.notifyQuickTimerExpired()
        }
        return true
    }
}
