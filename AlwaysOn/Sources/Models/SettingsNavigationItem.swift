import Foundation

/// Navigation items for the Settings window sidebar
enum SettingsNavigationItem: String, CaseIterable, Identifiable {
    case general
    case automation
    case updates
    case profiles
    case about
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .general: return "General"
        case .automation: return "Schedule"
        case .updates: return "Updates"
        case .profiles: return "Profiles"
        case .about: return "About"
        }
    }
    
    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .automation: return "calendar.badge.clock"
        case .updates: return "arrow.triangle.2.circlepath"
        case .profiles: return "person.2"
        case .about: return "info.circle"
        }
    }
}
