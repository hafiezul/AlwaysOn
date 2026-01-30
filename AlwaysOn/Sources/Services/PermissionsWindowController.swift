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
    
    /// Show the permissions window
    /// - Parameters:
    ///   - accessibilityPermission: The permission object to bind to
    ///   - onContinue: Called when user clicks Continue (permission granted)
    ///   - onQuit: Called when user clicks Quit
    @MainActor
    func show(
        accessibilityPermission: AccessibilityPermission,
        onContinue: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        // If window already exists, just bring it forward
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Start polling for permission changes
        accessibilityPermission.startPolling()
        
        // Create the SwiftUI view
        let permissionsView = PermissionsView(
            accessibilityPermission: accessibilityPermission,
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
        window.title = "Permissions"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .fullSizeContentView]
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.level = .floating
        window.center()
        
        // Store reference and show
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
