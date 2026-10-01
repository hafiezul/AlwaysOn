import Foundation

/// Quick timer duration options for auto-disable
enum QuickTimerDuration: Identifiable {
    case minutes30
    case hour1
    case hours2
    case hours4
    case hours8
    case noLimit
    case custom(minutes: Int)

    var id: String {
        switch self {
        case .minutes30: return "30m"
        case .hour1: return "1h"
        case .hours2: return "2h"
        case .hours4: return "4h"
        case .hours8: return "8h"
        case .noLimit: return "none"
        case .custom(let minutes): return "custom:\(minutes)"
        }
    }

    var title: String {
        switch self {
        case .minutes30: return "30 minutes"
        case .hour1: return "1 hour"
        case .hours2: return "2 hours"
        case .hours4: return "4 hours"
        case .hours8: return "8 hours"
        case .noLimit: return "No limit"
        case .custom(let minutes):
            if minutes == 60 { return "1 hour" }
            if minutes > 60 && minutes % 60 == 0 { return "\(minutes / 60) hours" }
            return "\(minutes) minutes"
        }
    }

    var menuTitle: String {
        switch self {
        case .minutes30: return "Keep Online for 30 min"
        case .hour1: return "Keep Online for 1 hour"
        case .hours2: return "Keep Online for 2 hours"
        case .hours4: return "Keep Online for 4 hours"
        case .hours8: return "Keep Online for 8 hours"
        case .noLimit: return "Keep Online (No limit)"
        case .custom(let minutes): return "Keep Online for \(minutes) min"
        }
    }

    /// Duration in seconds, nil for no limit
    var seconds: TimeInterval? {
        switch self {
        case .minutes30: return 30 * 60
        case .hour1: return 60 * 60
        case .hours2: return 2 * 60 * 60
        case .hours4: return 4 * 60 * 60
        case .hours8: return 8 * 60 * 60
        case .noLimit: return nil
        case .custom(let minutes): return TimeInterval(minutes * 60)
        }
    }

    /// Allowed range for custom durations in minutes
    static let customMinutesRange = 1...1440

    /// Create from stored string value
    static func from(id: String?) -> QuickTimerDuration {
        guard let id = id else { return .noLimit }
        if id.hasPrefix("custom:"),
           let minutes = Int(id.dropFirst("custom:".count)),
           customMinutesRange.contains(minutes) {
            return .custom(minutes: minutes)
        }
        return Self.allCases.first { $0.id == id } ?? .noLimit
    }
}

// Presets only; the custom case exists outside the preset pickers
extension QuickTimerDuration: CaseIterable {
    static var allCases: [QuickTimerDuration] {
        [.minutes30, .hour1, .hours2, .hours4, .hours8, .noLimit]
    }
}

extension QuickTimerDuration: Hashable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
