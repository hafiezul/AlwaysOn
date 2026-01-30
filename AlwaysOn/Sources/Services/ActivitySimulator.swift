import Foundation
import CoreGraphics
import AppKit

/// Simulates user activity to prevent system idle and keep apps like Teams showing "Available"
/// Uses minimal mouse movement (1 pixel) to avoid disrupting user work
final class ActivitySimulator {
    
    // MARK: - Properties
    
    private var timer: Timer?
    private var isRunning = false
    
    /// Tracks the last movement direction to alternate between +1 and -1 pixel
    private var moveDirection: CGFloat = 1
    
    // MARK: - Public Methods
    
    /// Start simulating activity at the specified interval
    /// - Parameter interval: Time in seconds between activity simulations (default: 45s)
    func start(interval: TimeInterval = 45.0) {
        guard !isRunning else { return }
        
        isRunning = true
        
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
        print("[ActivitySimulator] Started with interval: \(interval)s")
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
    
    /// Performs minimal mouse movement to simulate user activity
    /// Moves the cursor by 1 pixel, then back, to avoid visible movement
    private func simulateActivity() {
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
        
        #if DEBUG
        print("[ActivitySimulator] Activity simulated at \(Date())")
        #endif
    }
}
