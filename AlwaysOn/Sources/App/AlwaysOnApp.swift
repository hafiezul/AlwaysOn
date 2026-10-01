import SwiftUI

@main
struct AlwaysOnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    private var menuBarIconName: String {
        if appState.isActive {
            return "circle.fill"
        } else {
            return "circle"
        }
    }

    private var menuBarTimerText: String? {
        guard appState.isQuickTimerActive else { return nil }

        let remaining = appState.quickTimerRemaining
        guard remaining > 0 else { return nil }

        if remaining < 60 {
            return "\(Int(remaining))s"
        }

        return "\(Int((remaining / 60).rounded()))m"
    }
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: menuBarIconName)

                if let timerText = menuBarTimerText {
                    Text(timerText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - App Delegate

/// Handles app lifecycle events, particularly for showing the permissions window on first launch
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The menu bar scene needs a beat to install its window hooks before a dialog shows
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.handleAppLaunch()
        }
    }
    
    @MainActor
    private func handleAppLaunch() {
        let permission = AccessibilityPermission.shared
        
        // Show permissions window if:
        // 1. User hasn't completed onboarding, OR
        // 2. Permission is not currently granted
        if !permission.onboardingCompleted || !permission.hasPermission {
            PermissionsWindowController.shared.show(
                accessibilityPermission: permission,
                onContinue: {
                    permission.onboardingCompleted = true
                    // Back to steady-state polling now that the prompt is done
                    permission.stopPolling()
                    permission.startPolling(.standard)
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
