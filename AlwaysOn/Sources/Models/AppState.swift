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
                activitySimulator.start(interval: activityInterval)
            }
        }
    }
    
    /// Time since activation (for display purposes)
    @Published var activeSessionDuration: TimeInterval = 0
    
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
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Constants
    
    private enum Keys {
        static let isActive = "isActive"
        static let activityInterval = "activityInterval"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }
    
    private enum Defaults {
        static let activityInterval: TimeInterval = 45.0
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
        
        // Set default interval if not previously set
        if activityInterval == 0 {
            activityInterval = Defaults.activityInterval
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
    
    /// Toggle the active state
    func toggle() {
        if !isActive && !hasAccessibilityPermission {
            // Request permission and wait for it
            accessibilityPermission.request()
            return
        }
        isActive.toggle()
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
        
        activitySimulator.start(interval: activityInterval)
        sessionStartTime = Date()
        startSessionTimer()
    }
    
    private func stopActivitySimulation() {
        activitySimulator.stop()
        sessionTimer?.invalidate()
        sessionTimer = nil
        sessionStartTime = nil
        activeSessionDuration = 0
    }
    
    private func startSessionTimer() {
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.sessionStartTime else { return }
                self.activeSessionDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
}
