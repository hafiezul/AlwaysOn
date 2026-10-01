import Foundation
import Carbon.HIToolbox

/// Registers a system-wide hotkey and forwards key-down events.
/// Carbon's RegisterEventHotKey is the dependency-free way to get a global
/// shortcut in a menu bar app; SwiftUI keyboard shortcuts only fire inside
/// the app's own UI.
final class GlobalHotKeyManager {
    /// Fired on the main thread when the hotkey is pressed
    var onKeyDown: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// Registers a system-wide key-down shortcut, replacing any previous one
    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onKeyDown?() }
            return noErr
        }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, selfPointer, &eventHandler)
        guard installStatus == noErr else { return }

        var hotKeyID = EventHotKeyID(signature: OSType(0x414C5753), id: 1) // 'ALWS'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        eventHandler = nil
    }

    deinit {
        unregister()
    }
}
