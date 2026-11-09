import Foundation
import Combine

/// Stands in for the Sparkle-backed updater so the renderer builds without Sparkle
final class AppUpdater: NSObject, ObservableObject {
    static let shared = AppUpdater()
    let isConfigured = false
    @Published private(set) var canCheckForUpdates = false
    var lastUpdateCheckDate: Date? { nil }
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    func checkForUpdates() {}
}
