import Foundation

/// Opt-in, anonymous usage statistics sent to PostHog.
///
/// Off until the user turns it on. While on, AlwaysOn keeps a few counters on
/// this Mac and sends one rounded summary a day, plus the events listed in
/// `TelemetryEvent`. The only identifier is a random ID made when statistics
/// are turned on and deleted when they are turned off. Debug builds print
/// events instead of sending them.
@MainActor
final class TelemetryClient: ObservableObject {
    static let shared = TelemetryClient()

    enum Source: String {
        case setup, settings, menu
    }

    private enum Keys {
        static let enabled = "telemetryEnabled"
        static let installID = "telemetryInstallID"
        static let counters = "telemetryCounters"
        static let lastSummary = "telemetryLastSummary"
        static let lastVersion = "telemetryLastVersion"
        static let sentFirstSession = "telemetrySentFirstSession"
    }

    private enum Constants {
        /// A PostHog project token can only write events, so it is safe to ship in the app
        static let projectToken = "phc_m9GxX4qyh25oA538LiKpS7RM97mVRbpd28dQPTWEJnAB"
        static let captureURL = URL(string: "https://us.i.posthog.com/capture/")!
        static let summaryInterval: TimeInterval = 24 * 60 * 60
        /// How often to check whether a summary is due; the check itself is cheap
        static let checkInterval: TimeInterval = 3 * 60 * 60
    }

    @Published private(set) var isEnabled: Bool

    /// Builds the settings part of the daily summary; set by AppState
    var summaryProvider: (() -> TelemetryProperties)?

    private let defaults: UserDefaults
    private let session: URLSession
    private var checkTimer: Timer?
    private var isSendingSummary = false

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
        self.isEnabled = defaults.bool(forKey: Keys.enabled) && defaults.string(forKey: Keys.installID) != nil
    }

    // MARK: - Consent

    func setEnabled(_ enabled: Bool, source: Source) {
        guard enabled != isEnabled else { return }
        if enabled {
            defaults.set(UUID().uuidString, forKey: Keys.installID)
            defaults.set(true, forKey: Keys.enabled)
            defaults.set(Bundle.main.appVersion, forKey: Keys.lastVersion)
            isEnabled = true
            send(.enabled, properties: ["source": .string(source.rawValue)])
            startSchedule()
        } else {
            // Forget everything, so turning it back on starts as a new, unlinked install
            for key in [Keys.enabled, Keys.installID, Keys.counters, Keys.lastSummary,
                        Keys.lastVersion, Keys.sentFirstSession] {
                defaults.removeObject(forKey: key)
            }
            isEnabled = false
            checkTimer?.invalidate()
            checkTimer = nil
        }
    }

    // MARK: - Lifecycle

    /// Called once at launch: reports a version change and starts the daily check
    func start() {
        guard isEnabled else { return }
        let version = Bundle.main.appVersion
        if let previous = defaults.string(forKey: Keys.lastVersion), previous != version {
            send(.appUpdated, properties: ["from_version": .string(previous)])
        }
        defaults.set(version, forKey: Keys.lastVersion)
        startSchedule()
    }

    private func startSchedule() {
        checkTimer?.invalidate()
        let timer = Timer(timeInterval: Constants.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendSummaryIfDue() }
        }
        timer.tolerance = 30 * 60
        RunLoop.main.add(timer, forMode: .common)
        checkTimer = timer
        // Give launch a moment to settle before the first check
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            self?.sendSummaryIfDue()
        }
    }

    // MARK: - Counting

    func recordSessionStart(kind: SessionKind) {
        guard isEnabled else { return }
        updateCounters { $0.sessionsStarted[kind.rawValue, default: 0] += 1 }
        if !defaults.bool(forKey: Keys.sentFirstSession) {
            defaults.set(true, forKey: Keys.sentFirstSession)
            send(.firstSessionStarted, properties: ["kind": .string(kind.rawValue)])
        }
    }

    func recordAutoStop(_ reason: AutoStopEvent.Reason) {
        guard isEnabled else { return }
        updateCounters { $0.autoStops[TelemetryCounters.stopKey(reason), default: 0] += 1 }
    }

    func recordInputFailure() {
        guard isEnabled else { return }
        updateCounters { $0.inputFailures += 1 }
    }

    private var counters: TelemetryCounters {
        defaults.data(forKey: Keys.counters)
            .flatMap { try? JSONDecoder().decode(TelemetryCounters.self, from: $0) } ?? TelemetryCounters()
    }

    private func updateCounters(_ change: (inout TelemetryCounters) -> Void) {
        var current = counters
        change(&current)
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: Keys.counters)
        }
    }

    // MARK: - Daily Summary

    /// The properties the next daily summary would carry, for Settings to show
    func summaryProperties() -> TelemetryProperties {
        var properties = summaryProvider?() ?? [:]
        properties.merge(counters.properties) { _, counted in counted }
        return properties
    }

    /// The next daily summary exactly as it would be sent, with a placeholder ID
    func previewSummaryJSON() -> String {
        let capture = makeCapture(.dailySummary, properties: summaryProperties(),
                                  distinctID: "random ID, made when you turn this on")
        guard let data = try? capture.jsonData(prettyPrinted: true),
              let text = String(data: data, encoding: .utf8) else { return "" }
        // The token is the same for everyone; leave it out so the preview stays readable
        return text.replacingOccurrences(of: Constants.projectToken, with: "AlwaysOn project token")
    }

    private func sendSummaryIfDue(now: Date = Date()) {
        guard isEnabled, !isSendingSummary else { return }
        if let last = defaults.object(forKey: Keys.lastSummary) as? Date,
           now.timeIntervalSince(last) < Constants.summaryInterval, last <= now {
            return
        }
        let sentCounters = counters
        isSendingSummary = true
        send(.dailySummary, properties: summaryProperties()) { [weak self] delivered in
            guard let self else { return }
            self.isSendingSummary = false
            guard delivered, self.isEnabled else { return }
            self.defaults.set(now, forKey: Keys.lastSummary)
            // Keep anything counted while the request was in flight
            self.updateCounters { current in
                for (key, value) in sentCounters.sessionsStarted { current.sessionsStarted[key, default: 0] -= value }
                for (key, value) in sentCounters.autoStops { current.autoStops[key, default: 0] -= value }
                current.inputFailures -= sentCounters.inputFailures
                current.sessionsStarted = current.sessionsStarted.filter { $0.value > 0 }
                current.autoStops = current.autoStops.filter { $0.value > 0 }
                current.inputFailures = max(0, current.inputFailures)
            }
        }
    }

    // MARK: - Sending

    private func makeCapture(_ event: TelemetryEvent, properties: TelemetryProperties,
                             distinctID: String) -> TelemetryCapture {
        var all = TelemetryCapture.baseProperties(appVersion: Bundle.main.appVersion,
                                                  osVersion: ProcessInfo.processInfo.operatingSystemVersion)
        all.merge(properties) { _, specific in specific }
        return TelemetryCapture(apiKey: Constants.projectToken, event: event.rawValue,
                                distinctID: distinctID, properties: all, timestamp: Date())
    }

    private func send(_ event: TelemetryEvent, properties: TelemetryProperties = [:],
                      completion: ((Bool) -> Void)? = nil) {
        guard isEnabled, let installID = defaults.string(forKey: Keys.installID) else {
            completion?(false)
            return
        }
        let capture = makeCapture(event, properties: properties, distinctID: installID)
        guard let body = try? capture.jsonData() else {
            completion?(false)
            return
        }

        #if DEBUG
        print("[Telemetry] Not sent in debug builds: \(String(data: body, encoding: .utf8) ?? event.rawValue)")
        completion?(true)
        #else
        var request = URLRequest(url: Constants.captureURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        session.dataTask(with: request) { _, response, error in
            let delivered = error == nil && ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
            Task { @MainActor in completion?(delivered) }
        }.resume()
        #endif
    }
}
