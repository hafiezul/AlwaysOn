import Combine
import EventKit
import Foundation

/// Immutable copy of a calendar event, taken when events are loaded.
/// The end time is a snapshot: later edits in Calendar never change a running session.
struct CalendarEventSnapshot: Identifiable, Equatable {
    /// Unique per occurrence (recurring events share an `eventIdentifier`)
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarTitle: String?
}

/// What AlwaysOn may do with the user's calendars, independent of EventKit's OS-version-specific enum
enum CalendarAccessState: Equatable {
    case notDetermined
    case granted
    case denied
    /// Blocked by device policy (Screen Time, MDM); the user cannot change it in System Settings
    case restricted
    /// macOS 14+: only "add events" access was granted, which cannot read events
    case writeOnly
}

enum CalendarLoadPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

/// Read-only EventKit access. Never prompts on init or on reading status;
/// the permission prompt appears only inside `loadEvents()`, which the UI calls from an explicit button.
final class CalendarEventProvider: ObservableObject {
    /// Look-ahead window for "current or upcoming" events
    static let lookAhead: TimeInterval = 24 * 60 * 60

    @Published private(set) var accessState: CalendarAccessState
    @Published private(set) var phase: CalendarLoadPhase = .idle
    @Published private(set) var events: [CalendarEventSnapshot] = []

    private let store = EKEventStore()

    init() {
        accessState = Self.currentAccessState()
    }

    /// Request access if still undetermined, then fetch events for the next 24 hours.
    /// Excludes ended, all-day and canceled events. Never writes to the calendar.
    @MainActor
    func loadEvents() async {
        guard phase != .loading else { return }
        phase = .loading
        events = []

        if Self.currentAccessState() == .notDetermined {
            do {
                try await requestAccess()
            } catch {
                accessState = Self.currentAccessState()
                phase = .failed("Calendar access request failed: \(error.localizedDescription)")
                return
            }
        }

        accessState = Self.currentAccessState()
        guard accessState == .granted else {
            phase = .idle
            return
        }

        events = fetchEvents(now: Date())
        phase = .loaded
    }

    // MARK: - Private

    private func requestAccess() async throws {
        if #available(macOS 14.0, *) {
            _ = try await store.requestFullAccessToEvents()
        } else {
            _ = try await store.requestAccess(to: .event)
        }
    }

    private func fetchEvents(now: Date) -> [CalendarEventSnapshot] {
        let windowEnd = now.addingTimeInterval(Self.lookAhead)
        let predicate = store.predicateForEvents(withStart: now, end: windowEnd, calendars: nil)

        return store.events(matching: predicate)
            .filter { event in
                !event.isAllDay
                    && event.status != .canceled
                    && event.endDate > now
                    && event.startDate < windowEnd
            }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                let rawTitle = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let identifier = event.eventIdentifier ?? UUID().uuidString
                return CalendarEventSnapshot(
                    id: "\(identifier)@\(event.startDate.timeIntervalSince1970)",
                    title: rawTitle.isEmpty ? "Untitled event" : rawTitle,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    calendarTitle: event.calendar?.title
                )
            }
    }

    private static func currentAccessState() -> CalendarAccessState {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        default:
            break
        }

        if #available(macOS 14.0, *) {
            if status == .fullAccess { return .granted }
            if status == .writeOnly { return .writeOnly }
        } else if status == .authorized {
            return .granted
        }
        return .denied
    }
}
