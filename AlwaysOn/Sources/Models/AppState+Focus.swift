import Combine
import Foundation

/// Focus filter behavior: a Focus can keep you online and choose a profile
/// while it is on, and both are undone when it turns off
extension AppState {
    private enum FocusKeys {
        static let focusProfileId = "focusProfileId"
        static let profileBeforeFocus = "profileBeforeFocus"
    }

    /// The profile the active Focus switched to. Persisted so the previous
    /// profile still returns if AlwaysOn relaunches while the Focus is on.
    private var focusProfileId: UUID? {
        get { UserDefaults.standard.string(forKey: FocusKeys.focusProfileId).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: FocusKeys.focusProfileId) }
    }

    /// The profile in use before the Focus switched away from it
    private var profileBeforeFocus: UUID? {
        get { UserDefaults.standard.string(forKey: FocusKeys.profileBeforeFocus).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: FocusKeys.profileBeforeFocus) }
    }

    var isFocusSession: Bool {
        if case .focus? = sessionSource { return true }
        return false
    }

    /// Applies the current Focus filter values. Idempotent, so calls for a
    /// Focus turning on, turning off, or changing to another Focus all land
    /// in the right state.
    func applyFocusFilter(keepOnline: Bool, profileID: UUID?) {
        // A Focus that no longer keeps you online ends the session it started.
        // A session the user started or took over (by pausing and resuming) stays.
        if !keepOnline, isFocusSession {
            stopSession()
            lastAutoStop = AutoStopEvent(reason: .focusEnded, date: Date())
        }

        if let profileID, profileManager.profiles.contains(where: { $0.id == profileID }) {
            // Remember where to return only on the first switch, not when
            // one Focus hands over to another
            if focusProfileId == nil { profileBeforeFocus = profileManager.activeProfileId }
            focusProfileId = profileID
            focusRestoreProfileName = nil
            // Switching stops the current session, as choosing a profile in
            // the menu or Shortcuts does; a Focus is an explicit choice too
            if profileID != profileManager.activeProfileId { switchProfile(profileID) }
        } else if let focusProfile = focusProfileId {
            // Go back only if the user hasn't picked another profile since
            let previous = profileBeforeFocus.flatMap { id in profileManager.profiles.first { $0.id == id } }
            let canReturn = profileManager.activeProfileId == focusProfile && previous != nil && previous?.id != focusProfile
            if canReturn, hasActiveOrPausedSession, let previous {
                // Never stop the user's session to switch back: wait for it to
                // end, as a Wi-Fi profile switch does
                focusRestoreProfileName = previous.name
            } else {
                focusProfileId = nil
                profileBeforeFocus = nil
                focusRestoreProfileName = nil
                if canReturn, let previous { switchProfile(previous.id) }
            }
        }

        if keepOnline, !hasActiveOrPausedSession {
            accessibilityPermission.refresh()
            guard hasAccessibilityPermission else { return }
            stopSession()
            sessionSource = .focus
            isActive = true
        }
    }

    /// Finishes a switch back to the pre-Focus profile that waited for the
    /// user's session to end
    func setupFocusRestore() {
        Publishers.CombineLatest($isActive, $sessionSource)
            .debounce(for: .zero, scheduler: DispatchQueue.main)
            .sink { [weak self] _, _ in
                guard let self, self.focusRestoreProfileName != nil, !self.hasActiveOrPausedSession else { return }
                self.applyFocusFilter(keepOnline: false, profileID: nil)
            }
            .store(in: &cancellables)
    }

    /// Re-reads the Focus filter. Used at launch, after wake, and when the
    /// menu opens, in case a Focus change arrived while AlwaysOn couldn't act
    /// on it. Reads system state only; there is no polling.
    func refreshFocusFilter(onlyIfFocusOwnsSomething: Bool = true) {
        guard !onlyIfFocusOwnsSomething || isFocusSession || focusProfileId != nil else { return }
        Task { @MainActor [weak self] in
            guard let filter = try? await AlwaysOnFocusFilter.current else { return }
            self?.applyFocusFilter(keepOnline: filter.keepOnline, profileID: filter.profile?.id)
        }
    }
}
