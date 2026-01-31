import Foundation
import UserNotifications
import AppKit

/// Authorization status for notifications
enum NotificationAuthorizationStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case provisional
}

/// Manages local notifications for work schedule events
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    /// Whether notifications are enabled for work schedule events
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.notificationsEnabled)
            if isEnabled {
                requestAuthorization()
            }
        }
    }
    
    /// Current authorization status
    @Published private(set) var authorizationStatus: NotificationAuthorizationStatus = .notDetermined
    
    // MARK: - Private Properties
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // MARK: - Constants
    
    private enum Keys {
        static let notificationsEnabled = "workScheduleNotificationsEnabled"
    }
    
    private enum NotificationIdentifier: String {
        case workScheduleStarted = "com.alwayson.workschedule.started"
        case workScheduleEnded = "com.alwayson.workschedule.ended"
        case quickTimerExpired = "com.alwayson.quicktimer.expired"
    }
    
    private enum NotificationAction: String {
        case resume = "com.alwayson.action.resume"
    }
    
    private enum NotificationCategory: String {
        case quickTimerExpired = "com.alwayson.category.quicktimer"
    }
    
    // MARK: - Callbacks
    
    /// Called when user taps the resume action on quick timer expiration notification
    var onQuickTimerResumeTapped: (() -> Void)?
    
    // MARK: - Initialization
    
    override init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Keys.notificationsEnabled)
        super.init()
        notificationCenter.delegate = self
        
        // Register notification categories with actions
        registerNotificationCategories()
        
        // Check current authorization status on init
        Task {
            await checkAuthorizationStatus()
        }
    }
    
    // MARK: - Public Methods
    
    /// Check and update the current authorization status
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        await MainActor.run {
            switch settings.authorizationStatus {
            case .notDetermined:
                self.authorizationStatus = .notDetermined
            case .authorized:
                self.authorizationStatus = .authorized
            case .denied:
                self.authorizationStatus = .denied
            case .provisional:
                self.authorizationStatus = .provisional
            @unknown default:
                self.authorizationStatus = .notDetermined
            }
        }
    }
    
    /// Request authorization for notifications
    func requestAuthorization() {
        Task {
            do {
                let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
                await MainActor.run {
                    if granted {
                        self.authorizationStatus = .authorized
                    } else {
                        self.authorizationStatus = .denied
                        self.isEnabled = false
                    }
                }
            } catch {
                print("NotificationManager: Failed to request authorization: \(error)")
                await MainActor.run {
                    self.authorizationStatus = .denied
                    self.isEnabled = false
                }
            }
        }
    }
    
    /// Open System Settings to the Notifications pane
    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Send notification when work schedule starts
    func notifyWorkScheduleStarted() {
        guard isEnabled && authorizationStatus == .authorized else { return }
        
        sendNotification(
            identifier: .workScheduleStarted,
            title: "Work Hours Started",
            body: "AlwaysOn has automatically enabled activity simulation."
        )
    }
    
    /// Send notification when work schedule ends
    func notifyWorkScheduleEnded() {
        guard isEnabled && authorizationStatus == .authorized else { return }
        
        sendNotification(
            identifier: .workScheduleEnded,
            title: "Work Hours Ended",
            body: "AlwaysOn has automatically stopped the session."
        )
    }
    
    /// Send notification when quick timer expires during work hours
    func notifyQuickTimerExpired() {
        guard isEnabled && authorizationStatus == .authorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Quick Timer Expired"
        content.body = "Your activity timer has ended. Tap to resume keeping your status active."
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.quickTimerExpired.rawValue
        
        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.quickTimerExpired.rawValue,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("NotificationManager: Failed to add quick timer notification: \(error)")
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func registerNotificationCategories() {
        // Create resume action for quick timer expiration
        let resumeAction = UNNotificationAction(
            identifier: NotificationAction.resume.rawValue,
            title: "Resume",
            options: [.foreground]
        )
        
        // Create category with the action
        let quickTimerCategory = UNNotificationCategory(
            identifier: NotificationCategory.quickTimerExpired.rawValue,
            actions: [resumeAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Register the category
        notificationCenter.setNotificationCategories([quickTimerCategory])
    }
    
    private func sendNotification(identifier: NotificationIdentifier, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: identifier.rawValue,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("NotificationManager: Failed to add notification: \(error)")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notifications even when app is in foreground
        completionHandler([.banner, .sound])
    }
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification actions
        let actionIdentifier = response.actionIdentifier
        let notificationIdentifier = response.notification.request.identifier
        
        Task { @MainActor in
            // Check if this is the quick timer expiration notification and resume action was tapped
            if notificationIdentifier == NotificationIdentifier.quickTimerExpired.rawValue &&
               actionIdentifier == NotificationAction.resume.rawValue {
                self.onQuickTimerResumeTapped?()
            }
            
            // Also handle when user taps the notification body (not a specific action)
            if notificationIdentifier == NotificationIdentifier.quickTimerExpired.rawValue &&
               actionIdentifier == UNNotificationDefaultActionIdentifier {
                self.onQuickTimerResumeTapped?()
            }
        }
        
        completionHandler()
    }
}
