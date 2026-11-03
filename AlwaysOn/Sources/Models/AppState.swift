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
        }
    }

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
        }
    }
    
    /// Remaining time on the quick timer
    @Published var quickTimerRemaining: TimeInterval = 0
    
    /// Whether a quick timer is currently active
    var isQuickTimerActive: Bool {
        quickTimerEndTime != nil && isActive
    }
    
    // MARK: - Permission Management
    
    /// Accessibility permission state (Combine-based polling since macOS offers no change callback)
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
    private var sessionTimer: Timer?
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
        super.init()
        activitySimulator.gate.idleOnlyEnabled = simulateOnlyWhenIdle
        activitySimulator.gate.requireTargetApp = requireTargetApp
        activitySimulator.gate.targetBundleIDs = targetApps
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
        
        // Steady-state polling; onboarding temporarily raises the rate when its window opens
        accessibilityPermission.startPolling(.standard)
        
        // Resume active state if was active before quit (and has permission)
        if isActive && hasAccessibilityPermission {
            startActivitySimulation()
        } else if isActive && !hasAccessibilityPermission {
            // Reset active state if permissions are missing
            isActive = false
        } else if sessionSource?.chosenEndDate != nil {
            scheduleSessionHeartbeat()
        }
    }
    
    // MARK: - Public Methods
    
    /// Toggle the active state (pause/resume)
    func toggle() {
        if !isActive && !hasAccessibilityPermission {
            // Request permission and wait for it
            accessibilityPermission.request()
            return
        }
        
        if expireSessionIfNeeded() { return }
        sessionSource = sessionSource?.relinquishingCommand
        if isActive {
            // PAUSING - Save current session state
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
        if !isActive {
            sessionTimer?.invalidate()
            sessionTimer = nil
        }
        quickTimerRemaining = 0
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
                // Back to steady-state polling now that the prompt is done
                self.accessibilityPermission.stopPolling()
                self.accessibilityPermission.startPolling(.standard)
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )
    }

    /// Complete the permission setup (called after onboarding)
    func completePermissionSetup() {
        accessibilityPermission.onboardingCompleted = true
        // Back to steady-state polling now that onboarding is done
        accessibilityPermission.stopPolling()
        accessibilityPermission.startPolling(.standard)
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
        activitySimulator.deadline = sessionDeadline
        activitySimulator.start(interval: activityInterval, method: activityMethod)
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
        
        activitySimulator.deadline = sessionDeadline
        activitySimulator.start(interval: activityInterval, method: activityMethod)
        
        // Set session start time accounting for paused duration
        if pausedSessionDuration > 0 {
            // Resuming: Calculate start time to continue from paused duration
            sessionStartTime = Date().addingTimeInterval(-pausedSessionDuration)
        } else {
            // New session: Start from now
            sessionStartTime = Date()
        }
        
        scheduleSessionHeartbeat()
    }
    
    private func stopActivitySimulation() {
        activitySimulator.stop()
        
        // Stop the heartbeat but preserve duration for pause/resume
        sessionTimer?.invalidate()
        sessionTimer = nil
        if sessionDeadline != nil { scheduleSessionHeartbeat() }
        
        // Save current session duration for pause (don't reset to 0)
        // The pausedSessionDuration is set in toggle() before stopping
        
        // Stop updating the display while paused
        sessionStartTime = nil
        
        // Keep activeSessionDuration as-is for display while paused
        // Don't reset quickTimerRemaining - it will be calculated on resume
    }
    
    /// One per-second heartbeat drives both the session duration display and
    /// quick timer expiry, invalidating any previous heartbeat first so repeated
    /// startup paths (launch restore) can't stack timers
    private func scheduleSessionHeartbeat() {
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickSessionState()
            }
        }
        if let sessionTimer { RunLoop.main.add(sessionTimer, forMode: .common) }
    }
    
    private func tickSessionState() {
        if let startTime = sessionStartTime {
            activeSessionDuration = Date().timeIntervalSince(startTime)
        }
        
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
