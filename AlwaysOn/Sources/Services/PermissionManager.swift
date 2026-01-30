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
    /// - Returns: true if permission is now granted, false otherwise
    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Settings Navigation
    
    /// Opens System Settings/Preferences to the Privacy & Security > Accessibility section
    static func openAccessibilitySettings() {
        // macOS 13+ uses the new System Settings URL scheme
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Attempts to reset permission state by prompting the system
    /// This is useful after reinstalling the app
    static func promptForPermission() {
        // First, request with prompt - this will show system dialog if not already trusted
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        
        // If still not trusted after prompt, open settings as fallback
        if !isTrusted {
            // Give a moment for any system dialog to appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Check again - if still not trusted, the system dialog was likely suppressed
                // (happens when user previously denied or the entry exists but for old binary)
                if !checkAccessibilityPermission() {
                    openAccessibilitySettings()
                }
            }
        }
    }
}
