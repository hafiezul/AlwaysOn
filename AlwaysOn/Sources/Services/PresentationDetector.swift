import Foundation
import Combine
import AppKit
import CoreGraphics

/// Detects presentation/screen sharing mode to auto-pause activity
@MainActor
final class PresentationDetector: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Whether presentation detection is enabled
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.presentationDetectionEnabled)
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    
    /// Whether currently in presentation mode
    @Published private(set) var isPresentationActive: Bool = false
    
    /// Reason for presentation detection (for debugging/display)
    @Published private(set) var presentationReason: String?
    
    // MARK: - Private Properties
    
    private var checkTimer: Timer?
    private let checkInterval: TimeInterval = 3 // Check every 3 seconds
    
    /// Apps that typically indicate screen sharing/presentation
    private let presentationAppBundleIds: Set<String> = [
        "us.zoom.xos",                          // Zoom
        "com.microsoft.teams",                  // Microsoft Teams
        "com.microsoft.teams2",                 // Microsoft Teams (new)
        "com.webex.meetingmanager",             // Webex
        "com.cisco.webexmeetingsapp",           // Webex Meetings
        "com.google.Chrome.app.kjgfgldnnfobnciihpnb", // Google Meet (Chrome app)
        "com.skype.skype",                      // Skype
        "com.apple.FaceTime",                   // FaceTime
        "com.loom.desktop",                     // Loom
        "com.crowdcafe.windowmagnet",           // Screen recording apps
        "com.apple.ScreenSharing",              // Screen Sharing
        "com.apple.screencaptureui"             // Screenshot/Recording UI
    ]
    
    // MARK: - Constants
    
    private enum Keys {
        static let presentationDetectionEnabled = "presentationDetectionEnabled"
    }
    
    // MARK: - Callbacks
    
    /// Called when presentation state changes
    var onPresentationStateChanged: ((Bool) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Keys.presentationDetectionEnabled)
        
        // Initial check
        updatePresentationState()
        
        // Start monitoring if enabled
        if isEnabled {
            startMonitoring()
        }
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring for presentation mode
    func startMonitoring() {
        stopMonitoring()
        
        // Initial update
        updatePresentationState()
        
        // Start periodic checking
        checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePresentationState()
            }
        }
    }
    
    /// Stop monitoring presentation mode
    func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }
    
    /// Force a presentation state check
    func checkNow() {
        updatePresentationState()
    }
    
    // MARK: - Private Methods
    
    private func updatePresentationState() {
        let wasActive = isPresentationActive
        let (isPresenting, reason) = checkPresentationState()
        isPresentationActive = isPresenting
        presentationReason = reason
        
        // Notify if state changed
        if wasActive != isPresentationActive {
            onPresentationStateChanged?(isPresentationActive)
        }
    }
    
    /// Check for presentation/screen sharing state
    private func checkPresentationState() -> (isPresenting: Bool, reason: String?) {
        // Method 1: Check for screen recording/capture
        if let reason = checkScreenCapture() {
            return (true, reason)
        }
        
        // Method 2: Check for mirrored/extended displays
        if let reason = checkDisplayMirroring() {
            return (true, reason)
        }
        
        // Method 3: Check for known presentation apps with screen sharing active
        if let reason = checkPresentationApps() {
            return (true, reason)
        }
        
        return (false, nil)
    }
    
    /// Check if screen capture/recording is active
    private func checkScreenCapture() -> String? {
        // Check if any app is currently capturing the screen
        // This uses CGDisplayStream which requires screen recording permission
        // but we can detect if recording is happening without it
        
        // Check for active screen recording session
        if CGDisplayIsInMirrorSet(CGMainDisplayID()) != 0 {
            return "Screen is being mirrored"
        }
        
        // Check if screencaptureui or other capture utilities are running
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            if let bundleId = app.bundleIdentifier {
                if bundleId == "com.apple.screencaptureui" {
                    return "Screen capture active"
                }
            }
        }
        
        return nil
    }
    
    /// Check for display mirroring (external presentation)
    private func checkDisplayMirroring() -> String? {
        let maxDisplays: UInt32 = 16
        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0
        
        let error = CGGetOnlineDisplayList(maxDisplays, &onlineDisplays, &displayCount)
        guard error == .success else { return nil }
        
        // Check if any display is a mirror of another
        for i in 0..<Int(displayCount) {
            let displayId = onlineDisplays[i]
            
            // Check if this display is in a mirror set
            if CGDisplayIsInMirrorSet(displayId) != 0 {
                // Check if it's the primary in the mirror set or a mirror
                if CGDisplayMirrorsDisplay(displayId) != kCGNullDirectDisplay {
                    return "Display mirroring active"
                }
            }
        }
        
        return nil
    }
    
    /// Check for presentation apps that might be screen sharing
    private func checkPresentationApps() -> String? {
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }
            
            // Check if a known presentation app is the frontmost and active
            if presentationAppBundleIds.contains(bundleId) {
                // Additional heuristic: check if the app is frontmost or has a visible window
                // This helps distinguish between "app is running" vs "actively presenting"
                if app.isActive || app.activationPolicy == .regular {
                    // For video conferencing apps, we need to be smarter
                    // Just being open doesn't mean sharing screen
                    // We'll use a combination of factors
                    
                    // If Zoom/Teams is frontmost, there's a good chance of screen sharing
                    if app.isActive && isLikelyScreenSharing(app: app) {
                        return "Possible screen sharing: \(app.localizedName ?? bundleId)"
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Heuristic to determine if an app is likely screen sharing
    private func isLikelyScreenSharing(app: NSRunningApplication) -> Bool {
        guard let bundleId = app.bundleIdentifier else { return false }
        
        // For Zoom, check if there are multiple windows (share window + meeting window)
        // This is a rough heuristic
        if bundleId.contains("zoom") || bundleId.contains("teams") || bundleId.contains("webex") {
            // Check window count or other indicators
            // For now, we'll be conservative and not trigger on just having the app open
            // The user can manually pause if needed
            return false
        }
        
        // For screen recording specific apps
        if bundleId.contains("loom") || bundleId.contains("screencapture") {
            return true
        }
        
        return false
    }
    
    // MARK: - Status Info
    
    /// Human-readable status description
    var statusDescription: String {
        if !isEnabled {
            return "Disabled"
        }
        
        if isPresentationActive {
            return presentationReason ?? "Presentation detected - Paused"
        }
        
        return "Not presenting"
    }
    
    /// Icon for current state
    var statusIcon: String {
        if !isEnabled {
            return "rectangle.on.rectangle.slash"
        }
        return isPresentationActive ? "rectangle.inset.filled.on.rectangle" : "rectangle.on.rectangle"
    }
}
