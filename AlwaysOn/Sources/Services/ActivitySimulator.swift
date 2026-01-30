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
        switch activityMethod {
        case .mouse:
            simulateMouseActivity()
        case .keyboard:
            simulateKeyboardActivity()
        case .alternating:
            if lastMethodWasMouse {
                simulateKeyboardActivity()
            } else {
                simulateMouseActivity()
            }
            lastMethodWasMouse.toggle()
        }
        
        #if DEBUG
        print("[ActivitySimulator] Activity simulated at \(Date())")
        #endif
    }
    
    /// Performs minimal mouse movement to simulate user activity
    /// Moves the cursor by 1 pixel, then back, to avoid visible movement
    private func simulateMouseActivity() {
        // Get current mouse location
        let currentLocation = NSEvent.mouseLocation
        
        // Convert from bottom-left origin (AppKit) to top-left origin (CoreGraphics)
        guard let screen = NSScreen.main else { return }
        let screenHeight = screen.frame.height
        let cgPoint = CGPoint(x: currentLocation.x, y: screenHeight - currentLocation.y)
        
        // Calculate new position (move by 1 pixel)
        let newPoint = CGPoint(x: cgPoint.x + moveDirection, y: cgPoint.y)
        
        // Create and post mouse move event
        if let moveEvent = CGEvent(mouseEventSource: nil,
                                    mouseType: .mouseMoved,
                                    mouseCursorPosition: newPoint,
                                    mouseButton: .left) {
            moveEvent.post(tap: .cghidEventTap)
        }
        
        // Move back to original position after a tiny delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            if let returnEvent = CGEvent(mouseEventSource: nil,
                                         mouseType: .mouseMoved,
                                         mouseCursorPosition: cgPoint,
                                         mouseButton: .left) {
                returnEvent.post(tap: .cghidEventTap)
            }
            
            // Alternate direction for next time
            self?.moveDirection *= -1
        }
    }
    
    /// Performs keyboard activity by pressing and releasing the Shift key
    /// Shift is used because it doesn't produce any visible output
    private func simulateKeyboardActivity() {
        // Shift key virtual keycode
        let shiftKeyCode: CGKeyCode = 56
        
        // Create key down event
        if let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: shiftKeyCode, keyDown: true) {
            keyDownEvent.post(tap: .cghidEventTap)
        }
        
        // Release key after a tiny delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: shiftKeyCode, keyDown: false) {
                keyUpEvent.post(tap: .cghidEventTap)
            }
        }
    }
}
