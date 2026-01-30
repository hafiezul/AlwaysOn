import Foundation

/// Activity simulation methods available to the user
enum ActivityMethod: String, CaseIterable, Identifiable {
    case mouse = "mouse"
    case keyboard = "keyboard"
    case alternating = "alternating"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .mouse: return "Mouse Movement"
        case .keyboard: return "Keyboard"
        case .alternating: return "Alternating"
        }
    }
    
    var description: String {
        switch self {
        case .mouse:
            return "Simulates tiny mouse movements (1 pixel)"
        case .keyboard:
            return "Simulates keyboard activity (Shift key)"
        case .alternating:
            return "Alternates between mouse and keyboard"
        }
    }
    
    var systemImage: String {
        switch self {
        case .mouse: return "computermouse"
        case .keyboard: return "keyboard"
        case .alternating: return "arrow.triangle.2.circlepath"
        }
    }
}
