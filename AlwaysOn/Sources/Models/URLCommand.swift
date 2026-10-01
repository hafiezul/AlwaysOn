import Foundation

/// Commands accepted through the alwayson:// URL scheme
enum URLCommand: Equatable {
    case start
    case stop
    case toggle
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
