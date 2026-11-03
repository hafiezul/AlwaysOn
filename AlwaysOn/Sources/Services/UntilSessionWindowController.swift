import SwiftUI
import AppKit

/// Window controller for the "Keep online until…" window
/// Mirrors SettingsWindowController: a retained NSWindow hosting SwiftUI content
final class UntilSessionWindowController {

    // MARK: - Singleton

    static let shared = UntilSessionWindowController()

    // MARK: - Properties

    private var windowController: NSWindowController?
    private var hostingController: NSHostingController<AnyView>?

    // MARK: - Public Methods

    /// Show the window, or bring the existing one to the front without resetting what the user entered
    func show(appState: AppState) {
        if let existingWindow = windowController?.window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = AnyView(
            UntilSessionView(onClose: { [weak self] in self?.close() })
                .environmentObject(appState)
        )

        let hostingController = NSHostingController(rootView: rootView)
        self.hostingController = hostingController

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Keep Online Until"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 460, height: 520))
        window.minSize = NSSize(width: 440, height: 480)
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
