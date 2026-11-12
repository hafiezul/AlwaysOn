import Foundation

/// Shared by the app and its bundled command line tool. No shell configuration is changed.
public struct CLIInstallation {
    public enum Status: Equatable {
        case absent
        case current
        case anotherApp(URL)
        case brokenOwnedLink
        case missingBundledCLI
        case conflict
    }

    public enum Failure: LocalizedError {
        case invalidApp, missingHelper, conflict(String)
        public var errorDescription: String? {
            switch self {
            case .invalidApp: return "Install the full AlwaysOn app and use its bundled command line tool."
            case .missingHelper: return "The AlwaysOn app is missing its executable Contents/Helpers/alwayson. Reinstall the full app."
            case .conflict(let path): return "Refusing to replace or remove unrelated entry: \(path)"
            }
        }
    }

    public let appURL: URL
    public let directory: URL
    public var helperURL: URL { appURL.appendingPathComponent("Contents/Helpers/alwayson") }
    public var linkURL: URL { directory.appendingPathComponent("alwayson") }

    public init(appURL: URL = Bundle.main.bundleURL,
                userHome: URL = FileManager.default.homeDirectoryForCurrentUser,
                directory: URL? = nil) {
        self.appURL = appURL.standardizedFileURL.resolvingSymlinksInPath()
        self.directory = (directory ?? userHome.appendingPathComponent(".local/bin")).standardizedFileURL
    }

    private static func metadata(_ app: URL) -> [String: Any]? {
        guard app.pathExtension == "app",
              let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "com.alwayson.app" else { return nil }
        return info
    }

    public var version: String? {
        guard let info = Self.metadata(appURL),
              let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else { return nil }
        return "\(version) (\(build))"
    }

    public func validate() throws {
        guard Self.metadata(appURL) != nil else { throw Failure.invalidApp }
        guard FileManager.default.isExecutableFile(atPath: helperURL.path),
              helperURL.resolvingSymlinksInPath() == helperURL else { throw Failure.missingHelper }
    }

    public static func owningApp(executableURL: URL) throws -> CLIInstallation {
        let binary = executableURL.standardizedFileURL.resolvingSymlinksInPath()
        let app = binary.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let installation = CLIInstallation(appURL: app)
        try installation.validate()
        guard binary == installation.helperURL else { throw Failure.invalidApp }
        return installation
    }

    private var linkTarget: URL? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path) else { return nil }
        return URL(fileURLWithPath: target, relativeTo: directory).standardizedFileURL
    }

    private var entryStatus: Status {
        guard let target = linkTarget else {
            return (try? FileManager.default.attributesOfItem(atPath: linkURL.path)) == nil ? .absent : .conflict
        }
        // Exact current-app destination remains owned even when the helper is missing.
        if target == helperURL {
            return FileManager.default.isExecutableFile(atPath: target.path) ? .current : .brokenOwnedLink
        }
        if let other = try? Self.owningApp(executableURL: target), target == other.helperURL {
            return .anotherApp(other.appURL)
        }
        return .conflict
    }

    public var canUninstall: Bool {
        switch entryStatus {
        case .current, .brokenOwnedLink: return true
        default: return false
        }
    }

    public var status: Status {
        guard (try? validate()) != nil else { return .missingBundledCLI }
        return entryStatus
    }

    public func install() throws {
        try validate()
        switch entryStatus {
        case .current: return
        case .anotherApp, .brokenOwnedLink:
            try FileManager.default.removeItem(at: linkURL)
        case .absent: break
        default: throw Failure.conflict(linkURL.path)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: helperURL)
    }

    public func uninstall() throws {
        switch entryStatus {
        case .absent: return
        case .current, .brokenOwnedLink:
            try FileManager.default.removeItem(at: linkURL)
        default: throw Failure.conflict(linkURL.path)
        }
    }
}

// MARK: - Session status

/// What the app is doing right now. The app rewrites this file whenever its
/// state changes and deletes it when it quits; `alwayson status` reads it.
/// The process ID lets a reader ignore a file left behind by a crash.
public struct SessionStatus: Codable, Equatable {
    public enum State: String, Codable {
        case active, paused, off
    }

    public static let currentVersion = 1

    public var version: Int
    public var pid: Int32
    public var state: State
    /// manual, schedule, timer, until, command, or focus; nil when off
    public var source: String?
    public var endsAt: Date?
    /// When a timed pause resumes on its own
    public var resumesAt: Date?
    /// Sleep, a locked screen, or a switched-out user is holding input back
    public var isSuspended: Bool
    public var hasAccessibilityPermission: Bool
    public var profile: String
    public var profiles: [String]

    public static func fileURL(userHome: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        userHome.appendingPathComponent("Library/Application Support/AlwaysOn/status.json")
    }

    /// The status at `url`, or nil when there is none, it can't be read, it
    /// is from another format version, or the app that wrote it has exited
    public static func read(from url: URL) -> SessionStatus? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let status = try? decoder.decode(SessionStatus.self, from: data),
              status.version == currentVersion, status.pid > 0,
              // Signal 0 only checks that the process exists
              kill(status.pid, 0) == 0 || errno == EPERM else { return nil }
        return status
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try encoded().write(to: url, options: .atomic)
    }

    /// The profile whose name matches `name`, ignoring case
    public func profileName(matching name: String) -> String? {
        profiles.first { $0.compare(name, options: .caseInsensitive) == .orderedSame }
    }

    /// Plain-text lines for `alwayson status`
    public var summaryLines: [String] {
        let clock = DateFormatter()
        clock.dateFormat = "yyyy-MM-dd HH:mm"
        var first: String
        switch state {
        case .active: first = "AlwaysOn is active"
        case .paused: first = "AlwaysOn is paused"
        case .off: first = "AlwaysOn is off"
        }
        if let source, state != .off { first += " (\(source))" }
        if state == .active, let endsAt { first += " until \(clock.string(from: endsAt))" }
        if state == .paused, let resumesAt { first += ", resuming at \(clock.string(from: resumesAt))" }
        var lines = [first + "."]
        if isSuspended { lines.append("Input is on hold while the Mac is asleep, locked, or switched to another user.") }
        if !profile.isEmpty { lines.append("Profile: \(profile)") }
        if !hasAccessibilityPermission { lines.append("Accessibility permission is missing.") }
        return lines
    }
}
