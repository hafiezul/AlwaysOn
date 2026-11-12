import Foundation
import Combine
import AppKit

/// Permission entry points, Combine observers that keep AppState in step
/// with its services, and activity history recording
extension AppState {
    // MARK: - Permission

    /// Request permission with system prompt
    func requestPermission() {
        accessibilityPermission.request()
    }
    
    /// Open System Preferences to grant accessibility permission
    func openAccessibilitySettings() {
        accessibilityPermission.openSettings()
    }
    
    /// Show the permissions window
    func showPermissionsWindow() {
        PermissionsWindowController.shared.show(
            appState: self,
            onContinue: { [weak self] in
                guard let self else { return }
                self.accessibilityPermission.onboardingCompleted = true
                // The prompt is done; later checks happen on demand
                self.accessibilityPermission.stopPolling()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )
    }

    /// Complete the permission setup (called after onboarding)
    func completePermissionSetup() {
        accessibilityPermission.onboardingCompleted = true
        // Onboarding is done; later checks happen on demand
        accessibilityPermission.stopPolling()
    }

    // MARK: - Observers

    func setupPermissionObserver() {
        // React to permission state changes
        accessibilityPermission.$hasPermission
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (hasPermission: Bool) in
                guard let self else { return }
                
                // If permission was revoked while active, stop simulation
                if !hasPermission && self.isActive {
                    self.isActive = false
                    self.lastAutoStop = AutoStopEvent(reason: .permissionRevoked, date: Date())
                }
            }
            .store(in: &cancellables)
    }
    
    /// Forward nested ObservableObject changes to trigger SwiftUI view updates
    func setupNestedObjectChangeForwarding() {
        // When nested ObservableObjects change, SwiftUI doesn't automatically detect it
        // because it only observes one level deep. We need to manually forward changes.
        
        accessibilityPermission.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: Void) in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        profileManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: Void) in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        notificationManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: Void) in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        wifiMonitor.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: Void) in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        activityHistory.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: Void) in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func setupNotificationCallbacks() {
        // Handle quick timer resume action from notification
        notificationManager.onQuickTimerResumeTapped = { [weak self] in
            guard let self else { return }
            // Resume activity if not already active
            self.accessibilityPermission.refresh()
            if !self.isActive && self.hasAccessibilityPermission {
                self.stopSession()
                self.sessionSource = .manual
                self.isActive = true
            }
        }
    }

    // MARK: - Activity History

    func setupActivityHistory() {
        // Coalesce the several property changes one action makes into one update
        Publishers.CombineLatest3($isActive, $systemSuspension, $sessionSource)
            .debounce(for: .zero, scheduler: DispatchQueue.main)
            .sink { [weak self] isActive, suspension, source in
                self?.activityHistory.update(isOnline: isActive && suspension == nil, kind: SessionKind(source))
            }
            .store(in: &cancellables)
    }

    /// Closes the running history segment; called when the app quits
    func prepareForTermination() {
        activityHistory.closeOpenSegment()
        powerAssertions.hold(nil)
        removeSessionStatus()
    }

    /// Online time today, including the running segment
    var onlineTimeToday: TimeInterval {
        activityHistory.ledger.today(now: Date())
    }

    // MARK: - Session Status

    /// Only the real app publishes status. Previews and the screenshot
    /// renderer build these sources too and must not overwrite the file.
    private var publishesSessionStatus: Bool {
        Bundle.main.bundleIdentifier == "com.alwayson.app"
    }

    /// Keeps the status file for the `alwayson` tool up to date. No timer:
    /// it reacts only to changes the app already makes.
    func setupSessionStatus() {
        guard publishesSessionStatus else { return }
        objectWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] (_: Void) in self?.writeSessionStatus() }
            .store(in: &cancellables)
        writeSessionStatus()
    }

    var sessionStatus: SessionStatus {
        let state: SessionStatus.State = isActive ? .active : (hasActiveOrPausedSession ? .paused : .off)
        return SessionStatus(version: SessionStatus.currentVersion,
                             pid: ProcessInfo.processInfo.processIdentifier,
                             state: state,
                             source: state == .off ? nil : SessionKind(sessionSource).rawValue,
                             endsAt: state == .off ? nil : sessionDeadline,
                             resumesAt: state == .paused ? autoResumeAt : nil,
                             isSuspended: isActive && systemSuspension != nil,
                             hasAccessibilityPermission: hasAccessibilityPermission,
                             profile: profileManager.activeProfile?.name ?? "",
                             profiles: profileManager.profiles.map(\.name))
    }

    func writeSessionStatus() {
        guard publishesSessionStatus else { return }
        let status = sessionStatus
        guard status != lastWrittenSessionStatus else { return }
        do {
            try status.write(to: SessionStatus.fileURL())
            lastWrittenSessionStatus = status
        } catch {
            #if DEBUG
            print("[AppState] Status write failed: \(error)")
            #endif
        }
    }

    private func removeSessionStatus() {
        guard publishesSessionStatus else { return }
        try? FileManager.default.removeItem(at: SessionStatus.fileURL())
    }
}
