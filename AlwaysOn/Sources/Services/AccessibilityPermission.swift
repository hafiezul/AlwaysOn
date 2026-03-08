import Foundation
import Combine
import ApplicationServices
import AppKit

/// Manages accessibility permission with Combine-based reactive state
/// Inspired by Ice's permission handling pattern
@MainActor
final class AccessibilityPermission: ObservableObject {
    
    // MARK: - Published State
    
    /// Whether the app currently has accessibility permission
    @Published private(set) var hasPermission: Bool = false
    
    // MARK: - Private Properties
    
    private var timerCancellable: AnyCancellable?
    
    // MARK: - Constants
    
    /// Human-readable title for the permission
    let title = "Accessibility"
    
    /// Explanation of why this permission is needed
    let details = [
        "Simulate mouse movement to keep your status active.",
        "Prevent apps from marking you as away or idle."
    ]
    
    /// URL to open System Settings to the Accessibility privacy pane
    let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    
    // MARK: - Initialization
    
    init() {
        // Check permission immediately on init
        hasPermission = checkPermission()
    }
    
    // MARK: - Permission Checking
    
    /// Check if the app has accessibility permission (without prompting)
    private func checkPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Public Methods
    
    /// Request accessibility permission (shows system prompt if not already granted)
    func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        
        // If the system dialog was suppressed (e.g., stale entry), open settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if !self.checkPermission() {
                self.openSettings()
            }
        }
    }
    
    /// Open System Settings to the Accessibility privacy pane
    func openSettings() {
        if let url = settingsURL {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Start continuous polling for permission changes (1-second interval)
    func startPolling() {
        // Don't start if already polling
        guard timerCancellable == nil else { return }
        
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .merge(with: Just(.now)) // Check immediately
            .sink { [weak self] _ in
                guard let self else { return }
                self.hasPermission = self.checkPermission()
            }
    }
    
    /// Stop polling for permission changes
    func stopPolling() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    /// Perform a single permission check and update state
    func refresh() {
        hasPermission = checkPermission()
    }
}
