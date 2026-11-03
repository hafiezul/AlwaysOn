import Foundation
import CoreGraphics
import AppKit

/// Simulates user activity to prevent system idle and keep apps like Teams showing "Available"
/// Supports mouse movement, keyboard activity, or alternating between both
final class ActivitySimulator {
    
    // MARK: - Properties
    
    private var timer: Timer?
    private var isRunning = false
    
    /// Current activity method
    private var activityMethod: ActivityMethod = .mouse
    
    /// Tracks the last movement direction to alternate between +1 and -1 pixel
    private var moveDirection: CGFloat = 1
    
    /// Tracks which method was used last (for alternating mode)
    private var lastMethodWasMouse = true

    /// Suppression rules evaluated before each tick
    var gate = ActivityGate()
    let pulseLog = PulseLog()
    var deadline: Date?

    /// Seconds since the last real or synthetic input event. Injectable for tests.
    /// kCGAnyInputEventType (~0) matches any input class; stable for binary compatibility.
    var idleSecondsProvider: () -> TimeInterval = {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                eventType: CGEventType(rawValue: ~0)!)
    }

    /// Whether any of the given bundle IDs is currently running. Injectable for tests.
    var hasRunningTargetProvider: (Set<String>) -> Bool = { bundleIDs in
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier.map(bundleIDs.contains) ?? false
        }
    }
    
    // MARK: - Public Methods
    
    /// Start simulating activity at the specified interval
    /// - Parameters:
    ///   - interval: Time in seconds between activity simulations (default: 45s)
    ///   - method: The activity simulation method to use
    func start(interval: TimeInterval = 45.0, method: ActivityMethod = .mouse) {
        guard !isRunning else { return }
        
        isRunning = true
        activityMethod = method
        
        // Use a repeating timer on the main run loop
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.simulateActivity()
        }
        
        // Ensure timer fires even when menu is open
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        
        // Perform initial activity simulation
        simulateActivity()
        
        #if DEBUG
        print("[ActivitySimulator] Started with interval: \(interval)s, method: \(method.title)")
        #endif
    }
    
    /// Update the activity method while running
    /// - Parameter method: The new activity method to use
    func updateMethod(_ method: ActivityMethod) {
        activityMethod = method
        #if DEBUG
        print("[ActivitySimulator] Method updated to: \(method.title)")
        #endif
    }
    
    /// Stop simulating activity
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        
        #if DEBUG
        print("[ActivitySimulator] Stopped")
        #endif
    }
    
    // MARK: - Private Methods
    
    /// Performs activity simulation based on the selected method
    private func simulateActivity() {
        if let deadline, deadline <= Date() { return }
        switch gate.decision(idleSeconds: idleSecondsProvider(),
                             hasRunningTarget: hasRunningTargetProvider(gate.targetBundleIDs)) {
        case .skip(.userActive): pulseLog.record(.userActive); return
        case .skip(.noTarget): pulseLog.record(.noTarget); return
        case .post: break
        }
        let posted: Bool

        switch activityMethod {
        case .mouse:
            posted = simulateMouseActivity()
        case .keyboard:
            posted = simulateKeyboardActivity()
        case .alternating:
            if lastMethodWasMouse {
                posted = simulateKeyboardActivity()
            } else {
                posted = simulateMouseActivity()
            }
            lastMethodWasMouse.toggle()
        }
        
        pulseLog.record(posted ? .posted : .inputCreationFailed)
        #if DEBUG
        print("[ActivitySimulator] Activity simulated at \(Date())")
        #endif
    }
    
    /// Performs minimal mouse movement to simulate user activity
    /// Moves the cursor by 1 pixel, then back, to avoid visible movement
    private func simulateMouseActivity() -> Bool {
        // Get current mouse location
        let currentLocation = NSEvent.mouseLocation
        
        // Convert from bottom-left origin (AppKit) to top-left origin (CoreGraphics)
        // using the screen the cursor is on; multi-display setups offset screen
        // origins, so a plain height subtraction would teleport the cursor
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(currentLocation) }) ?? NSScreen.main else { return false }
        let cgPoint = CGPoint(x: currentLocation.x, y: screen.frame.maxY - currentLocation.y)
        
        // Calculate new position (move by 1 pixel)
        let newPoint = CGPoint(x: cgPoint.x + moveDirection, y: cgPoint.y)
        
        // Create and post mouse move event
        guard let moveEvent = CGEvent(mouseEventSource: nil,
                                    mouseType: .mouseMoved,
                                    mouseCursorPosition: newPoint,
                                    mouseButton: .left),
              let returnEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                        mouseCursorPosition: cgPoint, mouseButton: .left) else { return false }
        moveEvent.post(tap: .cghidEventTap)
        
        // Move back to original position after a tiny delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            returnEvent.post(tap: .cghidEventTap)
            
            // Alternate direction for next time
            self?.moveDirection *= -1
        }
        return true
    }
    
    /// Performs keyboard activity by pressing and releasing the Shift key
    /// Shift is used because it doesn't produce any visible output
    private func simulateKeyboardActivity() -> Bool {
        // Shift key virtual keycode
        let shiftKeyCode: CGKeyCode = 56
        
        // Create key down event
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: shiftKeyCode, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: shiftKeyCode, keyDown: false) else { return false }
        keyDownEvent.post(tap: .cghidEventTap)
        
        // Release key after a tiny delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            keyUpEvent.post(tap: .cghidEventTap)
        }
        return true
    }
}
