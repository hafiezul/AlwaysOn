import Foundation
import Combine

/// Manages work schedule checking and auto-enable/disable based on configured hours
@MainActor
final class WorkScheduleManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Current work schedule configuration
    @Published var schedule: WorkSchedule {
        didSet {
            handleScheduleChange()
        }
    }
    
    /// Whether currently within scheduled work hours
    @Published private(set) var isWithinSchedule: Bool = false
    
    // MARK: - Private Properties
    
    private var checkTimer: Timer?
    private let checkInterval: TimeInterval = 60 // Check every minute
    
    // MARK: - Callbacks
    
    /// Called when schedule state changes (enters or exits work hours)
    var onScheduleStateChanged: ((Bool) -> Void)?
    
    // MARK: - Initialization
    
    init(schedule: WorkSchedule = .default) {
        self.schedule = schedule
        
        // Initial check
        updateScheduleState()
        
        // Start monitoring if schedule is already enabled
        // This ensures the timer runs after app restart with an enabled schedule
        if schedule.isEnabled {
            startMonitoring()
        }
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring the schedule
    func startMonitoring() {
        guard schedule.isEnabled else { return }
        
        // Stop any existing timer
        stopMonitoring()
        
        // Initial state update
        updateScheduleState()
        
        // Start periodic checking
        checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateScheduleState()
            }
        }
        
        // Also check immediately when the minute changes for precise transitions
        scheduleNextMinuteCheck()
    }
    
    /// Stop monitoring the schedule
    func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }
    
    /// Force a schedule check
    func checkNow() {
        updateScheduleState()
    }
    
    /// Toggle the schedule on/off
    func toggleEnabled() {
        schedule.isEnabled.toggle()
        if schedule.isEnabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }
    
    // MARK: - Private Methods
    
    private func updateScheduleState() {
        let wasWithinSchedule = isWithinSchedule
        isWithinSchedule = schedule.isCurrentlyWithinSchedule
        
        // Notify if state changed
        if wasWithinSchedule != isWithinSchedule {
            onScheduleStateChanged?(isWithinSchedule)
        }
    }
    
    private func scheduleNextMinuteCheck() {
        let calendar = Calendar.current
        let now = Date()
        let nextMinute = calendar.nextDate(after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)
        let delay = nextMinute.timeIntervalSince(now)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.schedule.isEnabled else { return }
            self.updateScheduleState()
            self.scheduleNextMinuteCheck()
        }
    }

    private func handleScheduleChange() {
        if schedule.isEnabled {
            startMonitoring()
        } else {
            stopMonitoring()
            updateScheduleState()
        }
    }
    
    // MARK: - Schedule Info
    
    /// Human-readable status description
    var statusDescription: String {
        guard schedule.isEnabled else {
            return "Schedule disabled"
        }
        
        if isWithinSchedule {
            if let timeUntilEnd = schedule.timeUntilEnd() {
                return "Active until \(schedule.endTimeString) (\(formatTimeInterval(timeUntilEnd)) remaining)"
            }
            return "Within scheduled hours"
        } else {
            if let timeUntilStart = schedule.timeUntilNextStart() {
                return "Next: \(schedule.startTimeString) (in \(formatTimeInterval(timeUntilStart)))"
            }
            return "Outside scheduled hours"
        }
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
