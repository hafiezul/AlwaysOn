import Foundation

/// Navigation items for the Settings window sidebar
enum SettingsNavigationItem: String, CaseIterable, Identifiable {
    case general
    case updates
    case about
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .general: return "General"
        case .updates: return "Updates"
        case .about: return "About"
        }
    }
    
    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .updates: return "arrow.triangle.2.circlepath"
        case .about: return "info.circle"
        }
    }
}
