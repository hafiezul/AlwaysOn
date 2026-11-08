import AppKit
import SwiftUI

/// Shows the global shortcut and records a new one on click. Esc cancels.
struct HotKeyRecorder: View {
    @EnvironmentObject var appState: AppState
    @State private var monitor: Any?
    @State private var problem: String?

    private var isRecording: Bool { appState.isRecordingHotKey }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    isRecording ? stopRecording() : startRecording()
                } label: {
                    Text(isRecording ? "Type shortcut…" : appState.globalHotKey.displayString)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .frame(minWidth: 96)
                }
                .help(isRecording ? "Press the new shortcut, or Esc to cancel" : "Click to record a new shortcut")
                .accessibilityLabel(isRecording ? "Recording shortcut" : "Shortcut \(appState.globalHotKey.displayString), click to change")

                if appState.globalHotKey != .default && !isRecording {
                    Button("Reset") {
                        problem = nil
                        appState.globalHotKey = .default
                    }
                    .help("Go back to \(HotKey.default.displayString)")
                }
            }
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        problem = nil
        appState.isRecordingHotKey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == HotKey.escapeKeyCode {
                stopRecording()
                return nil
            }
            switch HotKey.recorded(keyCode: event.keyCode,
                                   modifierFlags: event.modifierFlags,
                                   charactersIgnoringModifiers: event.charactersIgnoringModifiers) {
            case .success(let hotKey):
                appState.globalHotKey = hotKey
                stopRecording()
            case .failure(let error):
                problem = error.message
            }
            // Swallow the key so it doesn't also act on the Settings window
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if appState.isRecordingHotKey { appState.isRecordingHotKey = false }
    }
}
