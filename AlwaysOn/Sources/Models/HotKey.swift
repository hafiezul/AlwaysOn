import AppKit

/// A system-wide shortcut as Carbon's RegisterEventHotKey expects it, plus
/// the label to show for its key
struct HotKey: Codable, Equatable {
    /// Virtual key code (kVK_*)
    var keyCode: UInt32
    /// Carbon modifier mask (cmdKey, optionKey, ...)
    var modifiers: UInt32
    /// The key as shown to the user, such as "K" or "F5"
    var keyLabel: String

    // Carbon modifier bits, spelled out so this type needs no Carbon import
    static let commandMask: UInt32 = 1 << 8
    static let shiftMask: UInt32 = 1 << 9
    static let optionMask: UInt32 = 1 << 11
    static let controlMask: UInt32 = 1 << 12

    /// ⌥⌘K
    static let `default` = HotKey(keyCode: 40, modifiers: optionMask | commandMask, keyLabel: "K")

    /// Shortcut in Apple's modifier order: ⌃⌥⇧⌘ then the key
    var displayString: String {
        var text = ""
        if modifiers & Self.controlMask != 0 { text += "⌃" }
        if modifiers & Self.optionMask != 0 { text += "⌥" }
        if modifiers & Self.shiftMask != 0 { text += "⇧" }
        if modifiers & Self.commandMask != 0 { text += "⌘" }
        return text + keyLabel
    }

    // MARK: - Recording

    enum RecordingError: Error, Equatable {
        /// Plain keys and Shift-only combinations would fire while typing
        case needsModifier
        /// A key with no printable label, such as a modifier or media key
        case unsupportedKey

        var message: String {
            switch self {
            case .needsModifier: return "Include ⌘, ⌥, or ⌃, so the shortcut doesn't fire while you type."
            case .unsupportedKey: return "That key can't be used. Try a letter, number, or function key."
            }
        }
    }

    /// F1–F12, which may be used without modifiers
    static let functionKeyLabels: [UInt32: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]

    /// Keys whose typed characters don't make a readable label
    static let specialKeyLabels: [UInt32: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟"
    ]

    /// The Escape key, which cancels recording instead of being recorded
    static let escapeKeyCode: UInt16 = 53

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= commandMask }
        if flags.contains(.option) { mask |= optionMask }
        if flags.contains(.control) { mask |= controlMask }
        if flags.contains(.shift) { mask |= shiftMask }
        return mask
    }

    /// Builds a hotkey from a recorded key-down
    static func recorded(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags,
                         charactersIgnoringModifiers: String?) -> Result<HotKey, RecordingError> {
        let code = UInt32(keyCode)
        let modifiers = carbonModifiers(from: modifierFlags)
        let label: String
        if let function = functionKeyLabels[code] {
            label = function
        } else if let special = specialKeyLabels[code] {
            label = special
        } else if let characters = charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            label = characters.uppercased()
        } else {
            return .failure(.unsupportedKey)
        }
        let hasRealModifier = modifiers & (commandMask | optionMask | controlMask) != 0
        guard hasRealModifier || functionKeyLabels[code] != nil else { return .failure(.needsModifier) }
        return .success(HotKey(keyCode: code, modifiers: modifiers, keyLabel: label))
    }
}
