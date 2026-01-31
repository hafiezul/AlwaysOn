import Foundation
import Combine
import AppKit

/// Monitors macOS Focus/Do Not Disturb mode to pause activity during focus sessions
@MainActor
final class FocusModeMonitor: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Whether Focus mode integration is enabled
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.focusModeEnabled)
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    
    /// Current Focus/DND state
    @Published private(set) var isFocusModeActive: Bool = false
    
    // MARK: - Private Properties
    
    private var checkTimer: Timer?
    private var notificationObserver: NSObjectProtocol?
    private let checkInterval: TimeInterval = 5 // Check every 5 seconds
    
    // MARK: - Constants
    
    private enum Keys {
        static let focusModeEnabled = "focusModeEnabled"
    }
    
    // MARK: - Callbacks
    
    /// Called when Focus mode state changes
    var onFocusModeChanged: ((Bool) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Keys.focusModeEnabled)
        
        // Initial check
        updateFocusModeState()
        
        // Start monitoring if enabled
        if isEnabled {
            startMonitoring()
        }
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring Focus mode
    func startMonitoring() {
        stopMonitoring()
        
        // Initial update
        updateFocusModeState()
        
        // Start periodic checking (Focus API doesn't have change notifications)
        checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateFocusModeState()
            }
        }
        
        // Also listen for distributed notifications that might indicate Focus changes
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.donotdisturb.stateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateFocusModeState()
            }
        }
    }
    
    /// Stop monitoring Focus mode
    func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
        
        if let observer = notificationObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            notificationObserver = nil
        }
    }
    
    /// Force a Focus mode check
    func checkNow() {
        updateFocusModeState()
    }
    
    // MARK: - Private Methods
    
    private func updateFocusModeState() {
        let wasActive = isFocusModeActive
        isFocusModeActive = checkFocusModeState()
        
        // Notify if state changed
        if wasActive != isFocusModeActive {
            onFocusModeChanged?(isFocusModeActive)
        }
    }
    
    /// Check Focus mode state using available methods
    private func checkFocusModeState() -> Bool {
        // Method 1: Check the Focus assertions file (works on macOS 12+)
        // This is the most reliable public method
        if let focusState = checkFocusAssertions() {
            return focusState
        }
        
        // Method 2: Check the DND preferences (older method)
        if let dndState = checkDNDPreferences() {
            return dndState
        }
        
        // Method 3: Check notification center settings
        if let notificationState = checkNotificationCenterSettings() {
            return notificationState
        }
        
        return false
    }
    
    /// Check Focus assertions file (macOS 12+)
    private func checkFocusAssertions() -> Bool? {
        // Check the Focus status through user defaults
        // This monitors the Focus state without using private APIs
        let focusDefaults = UserDefaults(suiteName: "com.apple.controlcenter")
        
        // Check if there are any active Focus modes
        if let focusState = focusDefaults?.dictionary(forKey: "NSStatusItem Visible FocusModes") {
            // If FocusModes is visible, Focus might be active
            return !focusState.isEmpty
        }
        
        return nil
    }
    
    /// Check DND preferences (legacy method)
    private func checkDNDPreferences() -> Bool? {
        // Check the notification center preferences
        let ncDefaults = UserDefaults(suiteName: "com.apple.notificationcenterui")
        
        // doNotDisturb key (older macOS versions)
        if let dndEnabled = ncDefaults?.bool(forKey: "doNotDisturb") {
            return dndEnabled
        }
        
        return nil
    }
    
    /// Check Notification Center settings for DND state
    private func checkNotificationCenterSettings() -> Bool? {
        // Read the notification center plist
        let plistPath = NSHomeDirectory() + "/Library/Preferences/com.apple.ncprefs.plist"
        
        guard let plistData = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        
        // Check for DND scheduled or active states
        if let dndMirror = plist["dnd_prefs"] as? Data {
            // Parse the binary plist for DND state
            // This is a simplified check - full parsing would require more complex logic
            return dndMirror.count > 0
        }
        
        return nil
    }
    
    // MARK: - Status Info
    
    /// Human-readable status description
    var statusDescription: String {
        if !isEnabled {
            return "Disabled"
        }
        return isFocusModeActive ? "Focus mode active - Paused" : "No Focus mode"
    }
    
    /// Icon for current state
    var statusIcon: String {
        if !isEnabled {
            return "moon.circle"
        }
        return isFocusModeActive ? "moon.fill" : "moon"
    }
}
