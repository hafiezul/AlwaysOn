import Foundation

/// Commands accepted through the alwayson:// URL scheme
enum URLCommand: Equatable {
    case start
    case stop
    case until(date: Date)
    case toggle
    case run(token: UUID)
    case finish(token: UUID)
    /// nil minutes falls back to the active profile's default duration
    case timer(minutes: Int?)
}

struct URLCommandParser {
    static let scheme = "alwayson"

    /// Parses alwayson://start, alwayson://stop, alwayson://toggle, and
    /// alwayson://timer?minutes=30. Returns nil for anything else.
    static func command(from url: URL) -> URLCommand? {
        guard url.scheme?.lowercased() == scheme else { return nil }

        switch url.host?.lowercased() {
        case "start":
            return .start
        case "stop":
            return .stop
        case "toggle":
            return .toggle
        case "run", "finish":
            let tokens = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.filter { $0.name.lowercased() == "token" } ?? []
            guard tokens.count == 1, let value = tokens.first?.value,
                  let token = UUID(uuidString: value) else { return nil }
            return url.host?.lowercased() == "run" ? .run(token: token) : .finish(token: token)
        case "until":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.filter { $0.name.lowercased() == "date" } ?? []
            guard items.count == 1, let value = items.first?.value else { return nil }
            let formatter = ISO8601DateFormatter()
            var parsed = formatter.date(from: value)
            if parsed == nil {
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                parsed = formatter.date(from: value)
            }
            guard let date = parsed, date.timeIntervalSince1970.isFinite, date > Date() else { return nil }
            return .until(date: date)
        case "timer":
            let minutes = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name.lowercased() == "minutes" }?
                .value
                .flatMap { Int($0) }
            return .timer(minutes: minutes)
        default:
            return nil
        }
    }
}
