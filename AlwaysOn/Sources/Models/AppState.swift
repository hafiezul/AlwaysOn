import Foundation
import Combine
import AppKit

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
    private var permissionCheckTimer: Timer?
    private var permissionCheckCount: Int = 0
    
    // MARK: - Constants
    
    private enum Keys {
        static let isActive = "isActive"
        static let activityInterval = "activityInterval"
    }
    
    private enum Defaults {
        static let activityInterval: TimeInterval = 45.0
        static let permissionCheckInterval: TimeInterval = 2.0
        static let maxPermissionChecks: Int = 15 // 30 seconds max (15 * 2s)
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
        
        // Listen for app activation to re-check permissions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        
        // Resume active state if was active before quit
        if isActive && hasAccessibilityPermission {
            startActivitySimulation()
        } else if isActive && !hasAccessibilityPermission {
            // Reset active state if permissions are missing
            isActive = false
        }
    }
    
    deinit {
        stopPermissionPolling()
        NotificationCenter.default.removeObserver(self)
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
        let previousState = hasAccessibilityPermission
        hasAccessibilityPermission = PermissionManager.checkAccessibilityPermission()
        
        // If permission was just granted, stop polling
        if hasAccessibilityPermission && !previousState {
            stopPermissionPolling()
        }
        // If permission was just revoked, stop activity
        else if !hasAccessibilityPermission && previousState {
            if isActive {
                isActive = false
            }
        }
    }
    
    /// Open System Preferences to grant accessibility permission
    func openAccessibilitySettings() {
        PermissionManager.openAccessibilitySettings()
        // Start temporary polling after opening settings (30 seconds max)
        startPermissionPolling()
    }
    
    // MARK: - Private Methods
    
    @objc private func appDidBecomeActive() {
        // Re-check permissions when app becomes active
        checkPermissions()
    }
    
    private func startPermissionPolling() {
        // Reset counter and start/restart polling
        permissionCheckCount = 0
        stopPermissionPolling()
        
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: Defaults.permissionCheckInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            self.permissionCheckCount += 1
            self.checkPermissions()
            
            // Stop polling after max checks or if permission granted
            if self.hasAccessibilityPermission || self.permissionCheckCount >= Defaults.maxPermissionChecks {
                self.stopPermissionPolling()
            }
        }
    }
    
    private func stopPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
        permissionCheckCount = 0
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
            guard let self = self, let startTime = self.sessionStartTime else { return }
            self.activeSessionDuration = Date().timeIntervalSince(startTime)
        }
    }
}
