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
