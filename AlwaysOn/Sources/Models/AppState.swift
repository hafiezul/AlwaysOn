import Foundation
import Combine
import AppKit

/// Central state management for the AlwaysOn app
/// Keeps track of active status and coordinates with ActivitySimulator
@MainActor
final class AppState: ObservableObject {
    
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
    
    /// Accessibility permission state (Combine-based, continuous polling)
    let accessibilityPermission = AccessibilityPermission()
    
    /// Convenience accessor for permission state
    var hasAccessibilityPermission: Bool {
        accessibilityPermission.hasPermission
    }
    
    // MARK: - Smart Features (v1.3)
    
    /// Work schedule manager for auto-enable/disable during work hours
    let workScheduleManager: WorkScheduleManager

    /// Named profile manager for profile-scoped settings
    let profileManager: ProfileManager
    
    /// Focus mode monitor to respect Do Not Disturb
    let focusModeMonitor = FocusModeMonitor()
    
    /// Presentation detector to pause during screen sharing
    let presentationDetector = PresentationDetector()
    
    /// Notification manager for work schedule events
    let notificationManager = NotificationManager()
    
    /// Whether activity is paused due to smart features (Focus, Presentation, etc.)
    @Published private(set) var isSmartPaused: Bool = false
    
    /// Reason for smart pause (for UI display)
    @Published private(set) var smartPauseReason: String?
    
    // MARK: - Private Properties
    
    private let activitySimulator = ActivitySimulator()
    private var sessionTimer: Timer?
    private var sessionStartTime: Date?
    private var quickTimerCheckTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    /// Accumulated session duration when paused (for pause/resume functionality)
    private var pausedSessionDuration: TimeInterval = 0
    
    /// Saved quick timer end time when paused (for pause/resume functionality)
    private var pausedQuickTimerEndTime: Date?
    
    /// Whether activity was active before smart pause
    private var wasActiveBeforeSmartPause: Bool = false
    
    /// Whether the user manually stopped/paused during current work window
    /// This prevents auto-restart until the next work schedule window begins
    private var userManuallyStopped: Bool = false

    /// Prevent profile application from rewriting the active profile recursively
    private var isApplyingProfile = false

    /// Keep profile switches inactive even if the new schedule is currently active
    private var suppressScheduleAutoStart = false
    
    // MARK: - Constants
    
    private enum Keys {
        static let isActive = "isActive"
        static let activityInterval = "activityInterval"
        static let activityMethod = "activityMethod"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let quickTimerEndTime = "quickTimerEndTime"
        static let defaultTimerDuration = "defaultTimerDuration"
    }
    
    private enum Defaults {
        static let activityInterval: TimeInterval = 45.0
        static let activityMethod: ActivityMethod = .mouse
        static let defaultTimerDuration: QuickTimerDuration = .noLimit
    }
    
    // MARK: - Onboarding State
    
    /// Whether the user has completed the initial permission onboarding
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }
    
    /// Whether to show the permissions window on launch
    var needsPermissionsOnboarding: Bool {
        !hasCompletedOnboarding || !accessibilityPermission.hasPermission
    }
    
    // MARK: - Computed Properties
    
    // MARK: - Initialization
    
    init() {
        let defaults = UserDefaults.standard
        ProfileManager.migrateIfNeeded(defaults: defaults)

        let profileManager = ProfileManager(defaults: defaults)
        let initialProfile = profileManager.activeProfile ?? Profile.makeDefault(from: defaults)

        self.profileManager = profileManager
        self.workScheduleManager = WorkScheduleManager(schedule: initialProfile.workSchedule)

        // Restore persisted state
        self.isActive = defaults.bool(forKey: Keys.isActive)
        self.activityInterval = initialProfile.activityInterval > 0 ? initialProfile.activityInterval : Defaults.activityInterval
        self.activityMethod = initialProfile.activityMethod
        self.defaultTimerDuration = initialProfile.defaultTimerDuration
        
        // Set default interval if not previously set
        if activityInterval == 0 {
            activityInterval = Defaults.activityInterval
        }
        
        // Restore quick timer if still valid
        if let savedEndTime = defaults.object(forKey: Keys.quickTimerEndTime) as? Date {
            if savedEndTime > Date() {
                self.quickTimerEndTime = savedEndTime
            } else {
                // Timer expired while app was closed
                defaults.removeObject(forKey: Keys.quickTimerEndTime)
            }
        }
        
        // Set up Combine subscriptions
        setupPermissionObserver()
        setupSmartFeatureObservers()
        setupNestedObjectChangeForwarding()
        setupNotificationCallbacks()
        setupProfileSync()
        
        // Start permission polling
        accessibilityPermission.startPolling()
        
        // Resume active state if was active before quit (and has permission)
        if isActive && hasAccessibilityPermission {
            startActivitySimulation()
        } else if isActive && !hasAccessibilityPermission {
            // Reset active state if permissions are missing
            isActive = false
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
        
        if isActive {
            // PAUSING - Save current session state
            pausedSessionDuration = activeSessionDuration
            pausedQuickTimerEndTime = quickTimerEndTime
            // Mark that user manually stopped during this work window
            userManuallyStopped = true
        } else {
            // RESUMING - User is manually resuming, clear the manual stop flag
            userManuallyStopped = false
            
            // Restore saved session state if there was a saved session
            if pausedSessionDuration > 0 {
                // Resume from paused state
                // sessionStartTime will be set to calculate from pausedSessionDuration
            }
            
            // Restore quick timer if it was active when paused
            if let savedTimerEndTime = pausedQuickTimerEndTime {
                quickTimerEndTime = savedTimerEndTime
            } else {
                // No saved timer, apply default timer if set
                if let seconds = defaultTimerDuration.seconds {
                    quickTimerEndTime = Date().addingTimeInterval(seconds)
                } else {
                    quickTimerEndTime = nil
                }
            }
            
            // Clear smart pause when user manually toggles
            isSmartPaused = false
            smartPauseReason = nil
        }
        
        isActive.toggle()
    }
    
    /// Stop session completely (full reset)
    func stopSession() {
        // Mark that user manually stopped during this work window
        userManuallyStopped = true
        
        // Clear all session state
        pausedSessionDuration = 0
        pausedQuickTimerEndTime = nil
        quickTimerEndTime = nil
        quickTimerRemaining = 0
        activeSessionDuration = 0
        clearSmartPause()
        isActive = false
    }

    func applyProfile(_ profile: Profile) {
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
        userManuallyStopped = false
        quickTimerEndTime = nil
        quickTimerRemaining = 0
    }

    func clearSmartPause() {
        isSmartPaused = false
        smartPauseReason = nil
        wasActiveBeforeSmartPause = false
    }
    
    /// Start with a quick timer duration
    func startWithQuickTimer(_ duration: QuickTimerDuration) {
        if !hasAccessibilityPermission {
            accessibilityPermission.request()
            return
        }
        
        if let seconds = duration.seconds {
            quickTimerEndTime = Date().addingTimeInterval(seconds)
        } else {
            quickTimerEndTime = nil
        }
        
        if !isActive {
            isActive = true
        }
    }
    
    /// Cancel the quick timer but keep activity running
    func cancelQuickTimer() {
        quickTimerEndTime = nil
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
                self.hasCompletedOnboarding = true
                self.accessibilityPermission.stopPolling()
                // Start normal operation polling (less frequent when running normally)
                self.accessibilityPermission.startPolling()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )
    }
    
    /// Complete the permission setup (called after onboarding)
    func completePermissionSetup() {
        hasCompletedOnboarding = true
        accessibilityPermission.stopPolling()
        // Restart with normal polling
        accessibilityPermission.startPolling()
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
        
        focusModeMonitor.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: Void) in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        presentationDetector.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: Void) in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        workScheduleManager.objectWillChange
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
    
    private func setupSmartFeatureObservers() {
        // Work Schedule: Auto-enable/disable based on schedule
        workScheduleManager.onScheduleStateChanged = { [weak self] (isWithinSchedule: Bool) in
            guard let self else { return }
            Task { @MainActor in
                self.handleWorkScheduleChange(isWithinSchedule: isWithinSchedule)
            }
        }
        
        // Focus Mode: Pause when Focus is active
        focusModeMonitor.onFocusModeChanged = { [weak self] (isFocusActive: Bool) in
            guard let self else { return }
            Task { @MainActor in
                self.handleFocusModeChange(isFocusActive: isFocusActive)
            }
        }
        
        // Presentation Mode: Pause during presentations
        presentationDetector.onPresentationStateChanged = { [weak self] (isPresentationActive: Bool) in
            guard let self else { return }
            Task { @MainActor in
                self.handlePresentationModeChange(isPresentationActive: isPresentationActive)
            }
        }
    }
    
    private func setupNotificationCallbacks() {
        // Handle quick timer resume action from notification
        notificationManager.onQuickTimerResumeTapped = { [weak self] in
            guard let self else { return }
            // Resume activity if not already active
            if !self.isActive && self.hasAccessibilityPermission {
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
        profileManager.updateProfileSettings(profileManager.activeProfileId, from: self)
    }
    
    // MARK: - Smart Feature Handlers
    
    private func handleWorkScheduleChange(isWithinSchedule: Bool) {
        guard workScheduleManager.schedule.isEnabled else { return }
        
        if isWithinSchedule {
            // Entering work hours - this is a new work window
            // Reset the manual stop flag so automation works for this new window
            userManuallyStopped = false

            guard !suppressScheduleAutoStart else { return }
            
            // Auto-enable if not already active
            if !isActive && hasAccessibilityPermission {
                isActive = true
                notificationManager.notifyWorkScheduleStarted()
            }
        } else {
            // Exiting work hours - STOP the session (full reset, not pause)
            // This gives users a fresh start for the next work window
            // Handle both active sessions AND paused sessions (where pausedSessionDuration > 0)
            let hadActiveOrPausedSession = isActive || pausedSessionDuration > 0
            
            // Note: stopSession() sets userManuallyStopped=true, but we override it below
            // because this was automatic, not user-initiated
            stopSession()
            userManuallyStopped = false
            
            // Only send notification if there was actually a session to end
            if hadActiveOrPausedSession {
                notificationManager.notifyWorkScheduleEnded()
            }
        }
    }
    
    private func handleFocusModeChange(isFocusActive: Bool) {
        guard focusModeMonitor.isEnabled else { return }
        
        if isFocusActive && isActive && !isSmartPaused {
            // Smart pause due to Focus mode
            wasActiveBeforeSmartPause = true
            isSmartPaused = true
            smartPauseReason = "Focus mode active"
            activitySimulator.stop()
        } else if !isFocusActive && isSmartPaused && smartPauseReason == "Focus mode active" {
            // Resume from smart pause
            isSmartPaused = false
            smartPauseReason = nil
            if wasActiveBeforeSmartPause && isActive {
                restartActivitySimulatorWithCurrentSettings()
            }
        }
    }
    
    private func handlePresentationModeChange(isPresentationActive: Bool) {
        guard presentationDetector.isEnabled else { return }
        
        if isPresentationActive && isActive && !isSmartPaused {
            // Smart pause due to presentation
            wasActiveBeforeSmartPause = true
            isSmartPaused = true
            smartPauseReason = presentationDetector.presentationReason ?? "Presentation mode"
            activitySimulator.stop()
        } else if !isPresentationActive && isSmartPaused && (smartPauseReason?.contains("Presentation") == true || smartPauseReason?.contains("mirror") == true || smartPauseReason?.contains("Screen") == true) {
            // Resume from smart pause
            isSmartPaused = false
            smartPauseReason = nil
            if wasActiveBeforeSmartPause && isActive {
                restartActivitySimulatorWithCurrentSettings()
            }
        }
    }
    
    private func restartActivitySimulatorWithCurrentSettings() {
        activitySimulator.stop()
        activitySimulator.start(interval: activityInterval, method: activityMethod)
    }
    
    private func handleActiveStateChange() {
        if isActive {
            startActivitySimulation()
        } else {
            stopActivitySimulation()
        }
    }
    
    private func startActivitySimulation() {
        guard hasAccessibilityPermission else {
            isActive = false
            return
        }
        
        // Don't start if smart paused
        guard !isSmartPaused else { return }
        
        activitySimulator.start(interval: activityInterval, method: activityMethod)
        
        // Set session start time accounting for paused duration
        if pausedSessionDuration > 0 {
            // Resuming: Calculate start time to continue from paused duration
            sessionStartTime = Date().addingTimeInterval(-pausedSessionDuration)
        } else {
            // New session: Start from now
            sessionStartTime = Date()
        }
        
        startSessionTimer()
        startQuickTimerChecker()
    }
    
    private func stopActivitySimulation() {
        activitySimulator.stop()
        
        // Stop timers but preserve duration for pause/resume
        sessionTimer?.invalidate()
        sessionTimer = nil
        quickTimerCheckTimer?.invalidate()
        quickTimerCheckTimer = nil
        
        // Save current session duration for pause (don't reset to 0)
        // The pausedSessionDuration is set in toggle() before stopping
        
        // Stop updating the display while paused
        sessionStartTime = nil
        
        // Keep activeSessionDuration as-is for display while paused
        // Don't reset quickTimerRemaining - it will be calculated on resume
    }
    
    private func startSessionTimer() {
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.sessionStartTime else { return }
                self.activeSessionDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func startQuickTimerChecker() {
        quickTimerCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let endTime = self.quickTimerEndTime {
                    let remaining = endTime.timeIntervalSince(Date())
                    if remaining <= 0 {
                        // Timer expired - disable activity
                        self.quickTimerEndTime = nil
                        self.isActive = false
                        
                        // Send notification if timer expired during work hours
                        if self.workScheduleManager.schedule.isEnabled && self.workScheduleManager.isWithinSchedule {
                            self.notificationManager.notifyQuickTimerExpired()
                        }
                    } else {
                        self.quickTimerRemaining = remaining
                    }
                }
            }
        }
    }
    
    deinit {
        // Cleanup happens automatically
    }
}
