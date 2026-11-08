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

    /// Lands each check just past a minute boundary, after the schedule's minute flips
    private let transitionLead: TimeInterval = 0.5

    // MARK: - Callbacks
    
    /// Called when schedule state changes (enters or exits work hours)
    var onScheduleStateChanged: ((Bool) -> Void)?
    
    // MARK: - Initialization
    
    init(schedule: WorkSchedule = .default) {
        self.schedule = schedule
        
        if schedule.isEnabled {
            startMonitoring()
        } else {
            updateScheduleState()
        }
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring the schedule. Instead of polling, one timer waits for
    /// the next start or end time, so the app stays asleep between them.
    /// Callers re-check after wake and clock changes, when that timer may be stale.
    func startMonitoring() {
        guard schedule.isEnabled else { return }

        // Stop any existing timer
        stopMonitoring()

        // Initial state update
        updateScheduleState()
        scheduleNextCheck()
    }

    private func scheduleNextCheck() {
        checkTimer?.invalidate()
        checkTimer = nil
        guard schedule.isEnabled,
              let transition = schedule.nextTransition(after: Date()) else { return }
        let timer = Timer(fire: transition.addingTimeInterval(transitionLead), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updateScheduleState()
                self.scheduleNextCheck()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        checkTimer = timer
    }
    
    /// Stop monitoring the schedule
    func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }
    
    /// Force a schedule check
    func checkNow() {
        updateScheduleState()
        if schedule.isEnabled { scheduleNextCheck() }
    }
    
    /// Toggle the schedule on/off
    func toggleEnabled() {
        schedule.isEnabled.toggle()
    }
    
    // MARK: - Private Methods
    
    private func updateScheduleState() {
        let nowWithinSchedule = schedule.isCurrentlyWithinSchedule
        // Publish only real changes, so observers don't redraw on every check
        guard nowWithinSchedule != isWithinSchedule else { return }
        isWithinSchedule = nowWithinSchedule
        onScheduleStateChanged?(nowWithinSchedule)
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
        let now = Date()
        guard let next = schedule.nextTransition(after: now) else {
            return "No upcoming work hours"
        }
        let style: Date.FormatStyle.DateStyle = Calendar.current.isDate(next, inSameDayAs: now) ? .omitted : .abbreviated
        let time = next.formatted(date: style, time: .shortened)
        let wait = formatTimeInterval(next.timeIntervalSince(now))
        if isWithinSchedule {
            let isBreak = next != schedule.workdayEnd(on: now)
            return isBreak ? "Active until a break at \(time) (\(wait) remaining)" : "Active until \(time) (\(wait) remaining)"
        }
        return "Next: \(time) (in \(wait))"
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
