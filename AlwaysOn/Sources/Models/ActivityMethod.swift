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
            return "Simulates mouse activity without moving the pointer"
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

/// The kind of input a single tick posts
enum SimulatedInput: Equatable {
    case mouse, keyboard
}

extension ActivityMethod {
    /// Which input a tick posts. While another app plays video, mouse input
    /// is swapped for keyboard: players reveal their controls on any pointer
    /// event over the video, while a bare Shift tap leaves them hidden.
    /// - Parameters:
    ///   - lastWasMouse: For alternating, whether the previous tick was mouse
    ///   - mediaPlaying: Whether another app is keeping the display awake for playback
    func input(lastWasMouse: Bool, mediaPlaying: Bool) -> SimulatedInput {
        if mediaPlaying { return .keyboard }
        switch self {
        case .mouse: return .mouse
        case .keyboard: return .keyboard
        case .alternating: return lastWasMouse ? .keyboard : .mouse
        }
    }
}
