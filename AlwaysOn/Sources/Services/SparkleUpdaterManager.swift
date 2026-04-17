import Foundation
import Sparkle
import SwiftUI
import AppKit

/// ObservableObject wrapper around Sparkle's SPUUpdater for SwiftUI integration
final class SparkleUpdaterManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = SparkleUpdaterManager()
    
    // MARK: - Published Properties
    
    /// Whether an update check is in progress
    @Published var isCheckingForUpdates = false
    
    /// Whether the updater can check for updates (properly configured)
    @Published var canCheckForUpdates = false
    
    /// Last update check date
    @Published var lastUpdateCheckDate: Date?
    
    // MARK: - Sparkle Components
    
    private var updaterController: SPUStandardUpdaterController?
    private var windowObserver: NSObjectProtocol?
    private var sparkleWindowCloseObserver: NSObjectProtocol?
    
    /// Direct access to the updater for advanced operations
    var updater: SPUUpdater? {
        updaterController?.updater
    }

    var isEnabled: Bool {
        UpdateChecker.currentMode.usesSparkle
    }
    
    // MARK: - Initialization
    
    private override init() {
        super.init()

        guard isEnabled else { return }
        
        // Initialize the updater controller with self as userDriverDelegate
        // to handle window focus when update UI is shown
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        
        // Set up observation for updater state
        setupObservation()
        
        // Observe new windows to catch Sparkle's update window
        setupWindowObservation()
    }
    
    deinit {
        removeObserver(&windowObserver)
        removeObserver(&sparkleWindowCloseObserver)
    }
    
    // MARK: - Public Methods
    
    /// Check for updates (user-initiated)
    func checkForUpdates() {
        guard isEnabled, canCheckForUpdates, let updaterController else { return }
        updaterController.checkForUpdates(nil)
    }
    
    /// Check for updates in background (no UI unless update found)
    func checkForUpdatesInBackground() {
        guard isEnabled, canCheckForUpdates, let updater else { return }
        updater.checkForUpdatesInBackground()
    }
    
    // MARK: - Private Methods
    
    private func setupObservation() {
        guard let updater else { return }

        // Observe canCheckForUpdates
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
        
        // Observe lastUpdateCheckDate
        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastUpdateCheckDate)
    }
    
    /// Observe window notifications to catch Sparkle windows when they appear
    private func setupWindowObservation() {
        // Observe when new windows appear
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            self?.handleSparkleWindowIfNeeded(window)
        }
    }
    
    /// Check if window is a Sparkle update window and bring it to front
    private func handleSparkleWindowIfNeeded(_ window: NSWindow) {
        guard isCandidateWindow(window), isSparkleWindow(window) else { return }
        bringWindowToFront(window)
    }
    
    /// Safely bring a window to front
    private func bringWindowToFront(_ window: NSWindow) {
        guard window.canBecomeKey else { return }
        
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

// MARK: - SwiftUI View Extension

/// A view that can trigger Sparkle update checks
struct CheckForUpdatesView: View {
    @ObservedObject private var updaterManager = SparkleUpdaterManager.shared
    
    var body: some View {
        Button("Check for Updates...") {
            updaterManager.checkForUpdates()
        }
        .disabled(!updaterManager.isEnabled || !updaterManager.canCheckForUpdates)
    }
}

// MARK: - SPUStandardUserDriverDelegate

extension SparkleUpdaterManager: SPUStandardUserDriverDelegate {
    /// Called when Sparkle is about to show a modal alert or update window
    /// This is our opportunity to bring the app to the foreground
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NotificationCenter.default.post(name: .sparkleUpdateWindowWillShow, object: nil)
        
        // Bring the app to the foreground
        NSApp.activate(ignoringOtherApps: true)
        
        // Find and bring Sparkle's update window to the front after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.findAndFocusSparkleWindow(attempt: 0)
        }
    }
    
    /// Called when Sparkle dismisses the update window
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        // Restore settings window level when user interacts with update
    }
    
    /// Indicates that we want Sparkle to bring focus to its update window
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        return true
    }
    
    /// Find Sparkle's update window and bring it to front
    private func findAndFocusSparkleWindow(attempt: Int) {
        let candidateWindows = NSApp.windows.filter(isCandidateWindow)
        
        let sparkleWindow = candidateWindows.first(where: isSparkleWindow)
        
        if let window = sparkleWindow {
            bringWindowToFront(window)
            observeSparkleWindowClose(for: window)
            return
        }

        guard attempt < 4 else {
            notifySparkleWindowDidClose()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.findAndFocusSparkleWindow(attempt: attempt + 1)
        }
    }

    private func observeSparkleWindowClose(for window: NSWindow) {
        removeObserver(&sparkleWindowCloseObserver)

        sparkleWindowCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.removeObserver(&self.sparkleWindowCloseObserver)
                self.notifySparkleWindowDidClose()
            }
    }
    
    /// Restore the settings window level after Sparkle window is dismissed
    private func notifySparkleWindowDidClose() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .sparkleUpdateWindowDidClose, object: nil)
        }
    }

    private func removeObserver(_ observer: inout NSObjectProtocol?) {
        guard let token = observer else { return }
        NotificationCenter.default.removeObserver(token)
        observer = nil
    }

    private func isCandidateWindow(_ window: NSWindow) -> Bool {
        guard window.isVisible, window.canBecomeKey else { return false }
        guard window.title != "Settings" else { return false }

        let windowClass = String(describing: type(of: window))
        return !windowClass.contains("StatusBar") &&
               !windowClass.contains("MenuBar") &&
               !windowClass.contains("PopUp")
    }

    private func isSparkleWindow(_ window: NSWindow) -> Bool {
        let windowClass = String(describing: type(of: window))
        let windowTitle = window.title.lowercased()

        return windowClass.contains("SPU") ||
               windowTitle.contains("software update") ||
               windowTitle.contains("new version") ||
               windowTitle.contains("update available") ||
               windowTitle.contains("alwayson")
    }
}
