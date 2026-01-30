import Foundation
import Combine

/// Central state management for the AlwaysOn app
/// Keeps track of active status and coordinates with ActivitySimulator
final class AppState: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Whether the activity simulation is currently active
    @Published var isActive: Bool {
        didSet {
            UserDefaults.standard.set(isActive, forKey: Keys.isActive)
            handleActiveStateChange()
        }
    }
    
    /// Whether accessibility permissions are granted
    @Published var hasAccessibilityPermission: Bool = false
    
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
    
    // MARK: - Private Properties
    
    private let activitySimulator = ActivitySimulator()
    private var sessionTimer: Timer?
    private var sessionStartTime: Date?
    
    // MARK: - Constants
    
    private enum Keys {
        static let isActive = "isActive"
        static let activityInterval = "activityInterval"
    }
    
    private enum Defaults {
        static let activityInterval: TimeInterval = 45.0
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
        
        // Check permissions on init
        checkPermissions()
        
        // Resume active state if was active before quit
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
            PermissionManager.requestAccessibilityPermission()
            checkPermissions()
            return
        }
        isActive.toggle()
    }
    
    /// Check and update accessibility permission status
    func checkPermissions() {
        hasAccessibilityPermission = PermissionManager.checkAccessibilityPermission()
    }
    
    /// Open System Preferences to grant accessibility permission
    func openAccessibilitySettings() {
        PermissionManager.openAccessibilitySettings()
    }
    
    // MARK: - Private Methods
    
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
            guard let self = self, let startTime = self.sessionStartTime else { return }
            self.activeSessionDuration = Date().timeIntervalSince(startTime)
        }
    }
}
