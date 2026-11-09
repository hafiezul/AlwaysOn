import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

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

    /// Whether any of the given bundle IDs is currently running. AppState
    /// replaces this with a RunningAppMonitor lookup; injectable for tests.
    var hasRunningTargetProvider: (Set<String>) -> Bool = { bundleIDs in
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier.map(bundleIDs.contains) ?? false
        }
    }

    /// Whether macOS still trusts the app to post input. Checked each tick in
    /// place of a separate polling timer, because a tick is the only moment
    /// a revoked permission matters while a session runs.
    var permissionProvider: () -> Bool = { AXIsProcessTrusted() }

    /// Called on the main queue when a tick finds the permission revoked
    var onPermissionLost: (() -> Void)?

    /// Called on the main queue when macOS refuses to create an input event
    var onInputFailed: (() -> Void)?

    /// Whether to work out how long the user has been away. Off by default so
    /// a tick reads the idle time only when a feature needs it.
    var tracksRealInput = false
    private(set) var inputTracker = RealInputTracker(start: Date())

    /// Asked at each tick, before posting, with how long the user has been
    /// away (0 when not tracked). Return false to skip the tick because the
    /// session is being stopped.
    var shouldContinue: ((_ awayFor: TimeInterval) -> Bool)?
    
    // MARK: - Public Methods
    
    /// When ticks happen and whether they post. Updating it while running
    /// takes effect from the next scheduled tick.
    var schedule = PulseSchedule()

    /// Start simulating activity
    /// - Parameters:
    ///   - schedule: Pacing, interval, and energy saving for this session
    ///   - method: The activity simulation method to use
    func start(schedule: PulseSchedule, method: ActivityMethod = .mouse) {
        guard !isRunning else { return }
        
        isRunning = true
        self.schedule = schedule
        activityMethod = method
        // Starting or resuming happens at the Mac, so the user is present now
        inputTracker = RealInputTracker(start: Date())
        
        // Tick at once; each tick schedules the next
        tick()
        
        #if DEBUG
        print("[ActivitySimulator] Started: \(schedule.pacing.rawValue), interval \(schedule.effectiveInterval)s, post after \(schedule.postAfter)s, method: \(method.title)")
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
    
    /// Runs one tick and schedules the next. A one-shot timer per tick lets
    /// adaptive pacing sleep exactly until input is due instead of waking on
    /// a fixed cadence.
    private func tick() {
        let delay = simulateActivity()
        guard isRunning else { return }
        timer?.invalidate()
        // Tolerance lets macOS batch this wake-up with others; a few seconds'
        // drift is far inside any presence app's idle timeout
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = schedule.tolerance(for: delay)
        // Common modes keep the timer firing while the menu is open
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Performs activity simulation based on the selected method
    /// - Returns: Seconds until the next tick
    private func simulateActivity() -> TimeInterval {
        let now = Date()
        // Read the idle time at most once per tick, and only when needed
        var measuredIdle: TimeInterval?
        func idleSeconds() -> TimeInterval {
            if let measuredIdle { return measuredIdle }
            let value = idleSecondsProvider()
            measuredIdle = value
            return value
        }
        // Fixed pacing never needs the idle time to plan; adaptive always does
        func nextDelay() -> TimeInterval {
            schedule.pacing == .fixed ? schedule.effectiveInterval : schedule.nextDelay(idleSeconds: idleSeconds())
        }

        if let deadline, deadline <= now { return nextDelay() }
        guard permissionProvider() else {
            pulseLog.record(.permissionMissing)
            onPermissionLost?()
            return nextDelay()
        }

        if tracksRealInput { inputTracker.observe(idleSeconds: idleSeconds(), now: now) }
        if let shouldContinue,
           !shouldContinue(tracksRealInput ? inputTracker.awayDuration(now: now) : 0) {
            return nextDelay()
        }

        // Adaptive pacing waits until the user has been idle long enough
        if !schedule.isDue(idleSeconds: idleSeconds()) {
            pulseLog.record(.userActive)
            return nextDelay()
        }

        switch gate.decision(idleSeconds: idleSeconds(),
                             hasRunningTarget: hasRunningTargetProvider(gate.targetBundleIDs)) {
        case .skip(.userActive): pulseLog.record(.userActive); return nextDelay()
        case .skip(.noTarget): pulseLog.record(.noTarget); return nextDelay()
        case .post: break
        }
        let delay = nextDelay()
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
        
        if posted { inputTracker.recordSyntheticPost(at: now) }
        pulseLog.record(posted ? .posted : .inputCreationFailed)
        if !posted { onInputFailed?() }
        #if DEBUG
        print("[ActivitySimulator] Activity simulated at \(Date()); next tick in \(delay)s")
        #endif
        return delay
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
