import SwiftUI
import AppKit

/// Window controller for the Pulse Log window
/// Mirrors SettingsWindowController: a retained NSWindow hosting SwiftUI content
@MainActor
final class PulseLogWindowController {

    // MARK: - Singleton

    static let shared = PulseLogWindowController()

    // MARK: - Properties

    private var windowController: NSWindowController?
    private var hostingController: NSHostingController<AnyView>?

    // MARK: - Public Methods

    /// Show the window, or bring the existing one to the front
    func show(appState: AppState) {
        if let existingWindow = windowController?.window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // The view observes the log directly, so new records appear without reopening the window
        let rootView = AnyView(PulseLogView(pulseLog: appState.pulseLog))

        let hostingController = NSHostingController(rootView: rootView)
        self.hostingController = hostingController

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Pulse Log"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 580, height: 680))
        window.minSize = NSSize(width: 520, height: 560)
        window.center()
        window.level = .floating

        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close the window if open
    func close() {
        windowController?.close()
        windowController = nil
        hostingController = nil
    }
}
