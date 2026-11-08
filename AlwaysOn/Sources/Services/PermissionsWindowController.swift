import SwiftUI
import AppKit

/// Window controller for the permissions window
/// Handles showing/hiding and manages the window instance
final class PermissionsWindowController {
    
    // MARK: - Singleton
    
    static let shared = PermissionsWindowController()
    
    // MARK: - Properties
    
    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Show the setup window
    /// - Parameters:
    ///   - appState: State the permission rows read and act on
    ///   - onContinue: Called when user clicks Continue or Done
    ///   - onQuit: Called when user clicks Quit (first run only)
    @MainActor
    func show(
        appState: AppState,
        onContinue: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        let accessibilityPermission = appState.accessibilityPermission
        let isFirstRun = !accessibilityPermission.onboardingCompleted
        // If window already exists, just bring it forward
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Start polling so the window tracks permission changes from System Settings
        accessibilityPermission.startPolling(.onboarding)
        
        // Create the SwiftUI view
        let permissionsView = PermissionsView(
            appState: appState,
            isFirstRun: isFirstRun,
            onContinue: { [weak self] in
                self?.close()
                onContinue()
            },
            onQuit: { [weak self] in
                self?.close()
                onQuit()
            }
        )
        
        // Wrap in AnyView for type erasure
        let hostingController = NSHostingController(rootView: AnyView(permissionsView))
        self.hostingController = hostingController
        
        // Create the window
        let window = NSWindow(contentViewController: hostingController)
        window.title = isFirstRun ? "Set Up AlwaysOn" : "Permissions"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // First run must end with Continue or Quit; later visits close like any window
        window.styleMask = isFirstRun ? [.titled, .fullSizeContentView] : [.titled, .closable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.delegate = closeObserver
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.level = .floating
        window.center()
        
        // Store reference and show
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Clears state when the user closes the window with the close button
    private lazy var closeObserver = CloseObserver { [weak self] in
        self?.window = nil
        self?.hostingController = nil
        Task { @MainActor in AccessibilityPermission.shared.stopPolling() }
    }

    private final class CloseObserver: NSObject, NSWindowDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowWillClose(_ notification: Notification) { onClose() }
    }

    /// Close the permissions window
    func close() {
        window?.close()
        window = nil
        hostingController = nil
    }
    
    /// Check if the window is currently visible
    var isVisible: Bool {
        window?.isVisible ?? false
    }
}
