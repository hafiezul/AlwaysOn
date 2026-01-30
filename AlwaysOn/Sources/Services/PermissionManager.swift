import Foundation
import ApplicationServices
import AppKit

/// Manages accessibility permissions required for simulating user input
enum PermissionManager {
    
    // MARK: - Permission Checking
    
    /// Check if the app has accessibility permissions
    /// - Returns: true if accessibility is enabled, false otherwise
    static func checkAccessibilityPermission() -> Bool {
        // Check current permission status without prompting
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    /// Request accessibility permission from the user
    /// This will show the system prompt if permission hasn't been granted
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Settings Navigation
    
    /// Opens System Settings/Preferences to the Privacy & Security > Accessibility section
    static func openAccessibilitySettings() {
        // macOS 13+ uses the new System Settings URL scheme
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
