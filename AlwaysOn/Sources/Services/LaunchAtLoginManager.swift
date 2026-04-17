import Foundation
import ServiceManagement
import AppKit

/// Manages launch-at-login registration.
final class LaunchAtLoginManager {

    /// Whether the app is set to launch at login
    static var isEnabled: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
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
    }
}
