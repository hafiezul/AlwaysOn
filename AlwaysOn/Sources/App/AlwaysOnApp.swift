import SwiftUI

@main
struct AlwaysOnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.isActive ? "circle.fill" : "circle")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - App Delegate

/// Handles app lifecycle events, particularly for showing the permissions window on first launch
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Delay slightly to ensure the app is fully initialized
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.handleAppLaunch()
        }
    }
    
    @MainActor
    private func handleAppLaunch() {
        // Check if we need to show the permissions window
        let permission = AccessibilityPermission()
        
        // Show permissions window if:
        // 1. User hasn't completed onboarding, OR
        // 2. Permission is not currently granted
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        
        if !hasCompletedOnboarding || !permission.hasPermission {
            PermissionsWindowController.shared.show(
                accessibilityPermission: permission,
                onContinue: {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    permission.stopPolling()
                },
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup if needed
    }
}
