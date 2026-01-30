import SwiftUI
import AppKit

/// Window controller for the Settings window
/// Uses NSWindow directly for more control over window behavior
final class SettingsWindowController {
    
    // MARK: - Singleton
    
    static let shared = SettingsWindowController()
    
    // MARK: - Properties
    
    private var windowController: NSWindowController?
    private weak var appState: AppState?
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Show the settings window
    /// - Parameter appState: The app state to inject into the view
    func show(appState: AppState) {
        self.appState = appState
        
        // If window exists and is visible, just bring it to front
        if let existingWindow = windowController?.window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create the settings view with environment object
        let settingsView = SettingsView()
            .environmentObject(appState)
        
        let hostingController = NSHostingController(rootView: settingsView)
        
        // Create window with appropriate style
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 600, height: 400))
        window.minSize = NSSize(width: 580, height: 350)
        window.center()
        
        // Set window level to floating so it stays on top of menu bar
        window.level = .floating
        
        // Store reference and show
        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)
        
        // Activate the app to bring window to front
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Close the settings window if open
    func close() {
        windowController?.close()
        windowController = nil
    }
}
