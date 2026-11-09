import Foundation

/// The two requests AlwaysOn may make in its menu, and the rules that keep
/// them rare: usage statistics at most twice (the setup window's switch counts
/// as the first time), a GitHub star once, never both on the same day, and
/// never while a session is running. Kept on this Mac only.
struct MenuAsks: Codable, Equatable {
    enum Ask: Equatable {
        case usageStatistics(isLastAsk: Bool)
        case githubStar
    }

    static let statisticsReaskDelay: TimeInterval = 30 * 24 * 60 * 60
    static let maxStatisticsAsks = 2
    static let starAfterUse: TimeInterval = 14 * 24 * 60 * 60
    static let starAfterSessions = 10
    static let gapBetweenAsks: TimeInterval = 24 * 60 * 60

    /// First launch of a version with these asks; stands in for the install date
    var firstSeen: Date?
    /// Sessions started, counted on this Mac only to time the star request
    var sessionsStarted = 0
    /// Times the user was offered statistics and didn't turn them on
    var statisticsAsks = 0
    var statisticsLastAsked: Date?
    /// Turned statistics off, or answered the last ask: never ask again
    var statisticsDeclined = false
    var starAnswered = false
    /// When the user last answered either ask
    var lastAnswered: Date?

    /// The ask to show in the menu now, if any
    func current(now: Date, statisticsEnabled: Bool, hasSession: Bool) -> Ask? {
        guard !hasSession, let firstSeen else { return nil }
        if let lastAnswered, now.timeIntervalSince(lastAnswered) < Self.gapBetweenAsks { return nil }

        if !statisticsEnabled, !statisticsDeclined, statisticsAsks < Self.maxStatisticsAsks {
            let isDue = statisticsLastAsked.map { now.timeIntervalSince($0) >= Self.statisticsReaskDelay } ?? true
            if isDue { return .usageStatistics(isLastAsk: statisticsAsks + 1 >= Self.maxStatisticsAsks) }
        }

        if !starAnswered,
           sessionsStarted >= Self.starAfterSessions,
           now.timeIntervalSince(firstSeen) >= Self.starAfterUse {
            return .githubStar
        }
        return nil
    }

    mutating func noteLaunch(now: Date) {
        if firstSeen == nil { firstSeen = now }
    }

    mutating func noteSessionStarted() {
        sessionsStarted = min(sessionsStarted + 1, 1000)
    }

    /// The first-run setup window showed the statistics switch: that was the first ask
    mutating func noteSetupOffered(now: Date) {
        guard statisticsAsks == 0 else { return }
        statisticsAsks = 1
        statisticsLastAsked = now
    }

    /// The user turned statistics on from the menu
    mutating func acceptStatistics(now: Date) {
        lastAnswered = now
    }

    /// "Not Now" or "No Thanks"; after the last ask there is no other
    mutating func postponeStatistics(now: Date) {
        statisticsAsks += 1
        statisticsLastAsked = now
        lastAnswered = now
        if statisticsAsks >= Self.maxStatisticsAsks { statisticsDeclined = true }
    }

    /// Turning statistics off anywhere is a clear answer
    mutating func declineStatistics() {
        statisticsDeclined = true
    }

    mutating func answerStar(now: Date) {
        starAnswered = true
        lastAnswered = now
    }
}
