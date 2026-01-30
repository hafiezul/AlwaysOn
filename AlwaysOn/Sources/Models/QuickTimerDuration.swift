import Foundation

/// Quick timer duration options for auto-disable
enum QuickTimerDuration: CaseIterable, Identifiable {
    case minutes30
    case hour1
    case hours2
    case hours4
    case hours8
    case noLimit
    
    var id: String {
        switch self {
        case .minutes30: return "30m"
        case .hour1: return "1h"
        case .hours2: return "2h"
        case .hours4: return "4h"
        case .hours8: return "8h"
        case .noLimit: return "none"
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
        }
    }
    
    /// Create from stored string value
    static func from(id: String?) -> QuickTimerDuration {
        guard let id = id else { return .noLimit }
        return Self.allCases.first { $0.id == id } ?? .noLimit
    }
}
