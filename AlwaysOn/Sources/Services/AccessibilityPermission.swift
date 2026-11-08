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
        /// Fast checks while the user grants the permission from System Settings.
        /// There is no steady-state rate: after onboarding the app re-checks on
        /// demand (menu open, app activation, session start, each tick).
        case onboarding
        
        var interval: TimeInterval {
            switch self {
            case .onboarding: return 1.0
            }
        }
    }

    /// How long polling started by request() runs before giving up
    static let requestPollingTimeout: TimeInterval = 120
    
    // MARK: - Published State
    
    /// Whether the app currently has accessibility permission
    @Published private(set) var hasPermission: Bool = false
    
    // MARK: - Private Properties
    
    private var timerCancellable: AnyCancellable?
    private var activeRate: PollRate?
    private var pollingDeadline: Date?
    
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
        // Notice the grant soon after the user flips the switch in System Settings
        startPolling(.onboarding, timeout: Self.requestPollingTimeout)

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
    
    /// Poll for permission changes at the given rate. Polling stops by itself
    /// once permission is granted, or after `timeout` seconds when one is given.
    func startPolling(_ rate: PollRate, timeout: TimeInterval? = nil) {
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        if timerCancellable != nil, activeRate == rate {
            // An open-ended poll (onboarding window) outranks a timed one
            if pollingDeadline != nil { pollingDeadline = deadline }
            return
        }
        stopPolling()
        activeRate = rate
        pollingDeadline = deadline
        
        timerCancellable = Timer.publish(every: rate.interval, tolerance: rate.interval * 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pollOnce()
            }
        
        pollOnce()
    }

    private func pollOnce() {
        applyPermissionState()
        if hasPermission || pollingDeadline.map({ Date() >= $0 }) == true {
            stopPolling()
        }
    }
    
    /// Stop polling for permission changes
    func stopPolling() {
        timerCancellable?.cancel()
        timerCancellable = nil
        activeRate = nil
        pollingDeadline = nil
    }
}
