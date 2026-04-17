import Foundation
import Combine
import ApplicationServices
import AppKit

/// Observable accessibility permission state for onboarding UI.
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
    
    /// Starts polling so the UI updates after permission changes in Settings.
    func startPolling() {
        guard timerCancellable == nil else { return }

        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .merge(with: Just(.now))
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
