import Foundation
import Sparkle
import SwiftUI

/// ObservableObject wrapper around Sparkle's SPUUpdater for SwiftUI integration
final class SparkleUpdaterManager: ObservableObject {
    
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
    
    private let updaterController: SPUStandardUpdaterController
    
    /// Direct access to the updater for advanced operations
    var updater: SPUUpdater {
        updaterController.updater
    }
    
    // MARK: - Initialization
    
    private init() {
        // Initialize the updater controller
        // startingUpdater: true means it will start automatically
        // updaterDelegate: nil for default behavior
        // userDriverDelegate: nil for default UI
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        
        // Set up observation for updater state
        setupObservation()
    }
    
    // MARK: - Public Methods
    
    /// Check for updates (user-initiated)
    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        updaterController.checkForUpdates(nil)
    }
    
    /// Check for updates in background (no UI unless update found)
    func checkForUpdatesInBackground() {
        guard canCheckForUpdates else { return }
        updater.checkForUpdatesInBackground()
    }
    
    // MARK: - Private Methods
    
    private func setupObservation() {
        // Observe canCheckForUpdates
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
        
        // Observe lastUpdateCheckDate
        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastUpdateCheckDate)
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
        .disabled(!updaterManager.canCheckForUpdates)
    }
}
