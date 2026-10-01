import Foundation
import Combine
import ApplicationServices
import AppKit

/// Observable accessibility permission state for onboarding UI.
/// There is exactly one permission state per app instance, so every
/// consumer binds to the shared object.
@MainActor
final class AccessibilityPermission: ObservableObject {
    
    // MARK: - Shared Instance
    
    static let shared = AccessibilityPermission()
    
    /// How often the permission state is checked while polling
    enum PollRate {
        /// Fast checks while the user grants the permission from System Settings
        case onboarding
        /// Slower steady-state checks to notice revocations after onboarding
        case standard
        
        var interval: TimeInterval {
            switch self {
            case .onboarding: return 1.0
            case .standard: return 10.0
            }
        }
    }
    
    // MARK: - Published State
    
    /// Whether the app currently has accessibility permission
    @Published private(set) var hasPermission: Bool = false
    
    // MARK: - Private Properties
    
    private var timerCancellable: AnyCancellable?
    private var activeRate: PollRate?
    
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
    
    // MARK: - Onboarding State
    
    /// Whether the user has completed the initial permission onboarding
    var onboardingCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }
    
    // MARK: - Initialization
    
    private init() {
        hasPermission = checkPermission()
    }
    
    // MARK: - Permission Checking
    
    /// Check if the app has accessibility permission (without prompting)
    private func checkPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    /// Update published state only when the check result changes
    private func applyPermissionState() {
        let granted = checkPermission()
        guard granted != hasPermission else { return }
        hasPermission = granted
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
    
    /// Check permission once and update state
    func refresh() {
        applyPermissionState()
    }
    
    /// Poll for permission changes at the given rate
    func startPolling(_ rate: PollRate) {
        if timerCancellable != nil, activeRate == rate { return }
        if activeRate != rate {
            stopPolling()
        }
        activeRate = rate
        
        timerCancellable = Timer.publish(every: rate.interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.applyPermissionState()
            }
        
        applyPermissionState()
    }
    
    /// Stop polling for permission changes
    func stopPolling() {
        timerCancellable?.cancel()
        timerCancellable = nil
        activeRate = nil
    }
}
