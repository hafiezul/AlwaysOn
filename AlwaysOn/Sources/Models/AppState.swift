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
            UserDefaults.standard.set(activityInterval, forKey: Keys.activityInterval)
            if isActive {
                // Restart simulator with new interval
                activitySimulator.stop()
                activitySimulator.start(interval: activityInterval, method: activityMethod)
            }
        }
    }
    
    /// Current activity simulation method
    @Published var activityMethod: ActivityMethod {
        didSet {
            UserDefaults.standard.set(activityMethod.rawValue, forKey: Keys.activityMethod)
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
            UserDefaults.standard.set(defaultTimerDuration.id, forKey: Keys.defaultTimerDuration)
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
    
    // MARK: - Initialization
    
    init() {
        // Restore persisted state
        self.isActive = UserDefaults.standard.bool(forKey: Keys.isActive)
        self.activityInterval = UserDefaults.standard.double(forKey: Keys.activityInterval)
        
        // Restore activity method
        if let methodRaw = UserDefaults.standard.string(forKey: Keys.activityMethod),
           let method = ActivityMethod(rawValue: methodRaw) {
            self.activityMethod = method
        } else {
            self.activityMethod = Defaults.activityMethod
        }
        
        // Restore default timer duration
        if let durationId = UserDefaults.standard.string(forKey: Keys.defaultTimerDuration) {
            self.defaultTimerDuration = QuickTimerDuration.from(id: durationId)
        } else {
            self.defaultTimerDuration = Defaults.defaultTimerDuration
        }
        
        // Set default interval if not previously set
        if activityInterval == 0 {
            activityInterval = Defaults.activityInterval
        }
        
        // Restore quick timer if still valid
        if let savedEndTime = UserDefaults.standard.object(forKey: Keys.quickTimerEndTime) as? Date {
            if savedEndTime > Date() {
                self.quickTimerEndTime = savedEndTime
            } else {
                // Timer expired while app was closed
                UserDefaults.standard.removeObject(forKey: Keys.quickTimerEndTime)
            }
        }
        
        // Set up Combine subscriptions
        setupPermissionObserver()
        
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
        } else {
            // RESUMING - Restore saved session state
            // If there was a saved session, restore it
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
        }
        
        isActive.toggle()
    }
    
    /// Stop session completely (full reset)
    func stopSession() {
        // Clear all session state
        pausedSessionDuration = 0
        pausedQuickTimerEndTime = nil
        quickTimerEndTime = nil
        activeSessionDuration = 0
        isActive = false
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
