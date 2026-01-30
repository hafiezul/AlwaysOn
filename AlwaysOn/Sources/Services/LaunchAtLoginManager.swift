import Foundation
import ServiceManagement
import AppKit

/// Manages launch at login functionality using SMAppService (macOS 13+)
final class LaunchAtLoginManager {
    
    // MARK: - Properties
    
    /// Whether the app is set to launch at login
    static var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                // Fallback for older macOS (shouldn't happen since we require 13.0+)
                return UserDefaults.standard.bool(forKey: "launchAtLogin")
            }
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("LaunchAtLoginManager: Failed to \(newValue ? "enable" : "disable") launch at login: \(error)")
                }
            }
            // Also store in UserDefaults for UI state consistency
            UserDefaults.standard.set(newValue, forKey: "launchAtLogin")
        }
    }
    
    /// Current status description for debugging
    @available(macOS 13.0, *)
    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            return "Not registered"
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Requires approval in System Settings"
        case .notFound:
            return "App not found"
        @unknown default:
            return "Unknown status"
        }
    }
    
    // MARK: - Methods
    
    /// Toggle launch at login
    static func toggle() {
        isEnabled = !isEnabled
    }
    
    /// Open System Settings to Login Items (if user needs to approve manually)
    @available(macOS 13.0, *)
    static func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
