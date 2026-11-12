import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

func diagnostic(_ message: String) {
    FileHandle.standardError.write(Data("alwayson: \(message)\n".utf8))
}

// Only the signal handler and the main thread access this PID. Signals are
// blocked while the main thread changes it; the handler uses only kill(2).
var childPID: pid_t = 0
func forwardSignal(_ number: Int32) {
    if number != SIGINT && childPID > 0 { _ = kill(childPID, number) }
}

func executable(_ name: String) -> String? {
    if name.contains("/") { return name }
    return (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":", omittingEmptySubsequences: false)
        .map { ($0.isEmpty ? "." : String($0)) + "/" + name }
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}

func spawnAndWait(_ arguments: [String], forwarding: Bool = false) -> Int32 {
    guard let path = executable(arguments[0]) else { diagnostic("executable not found: \(arguments[0])"); return 127 }
    var blocked = sigset_t()
    sigemptyset(&blocked)
    for s in [SIGINT, SIGTERM, SIGHUP] { sigaddset(&blocked, s) }
    var oldMask = sigset_t()
    if forwarding { sigprocmask(SIG_BLOCK, &blocked, &oldMask) }
    return spawnPlatform(path, arguments, forwarding, &blocked, &oldMask)
}

func spawnPlatform(_ path: String, _ arguments: [String], _ forwarding: Bool,
                   _ blocked: inout sigset_t, _ oldMask: inout sigset_t) -> Int32 {
    #if canImport(Darwin)
    var attributes: posix_spawnattr_t? = nil
    #else
    var attributes = posix_spawnattr_t()
    #endif
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    var defaults = sigset_t()
    sigemptyset(&defaults)
    for s in [SIGINT, SIGTERM, SIGHUP] { sigaddset(&defaults, s) }
    posix_spawnattr_setsigdefault(&attributes, &defaults)
    var mask = forwarding ? oldMask : sigset_t()
    if !forwarding { sigemptyset(&mask) }
    posix_spawnattr_setsigmask(&attributes, &mask)
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
    let argv = arguments.map { strdup($0) } + [nil]
    defer { for pointer in argv { free(pointer) } }
    var pid: pid_t = 0
    let environment = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer { for pointer in environment { free(pointer) } }
    let error = argv.withUnsafeBufferPointer { buffer in
        environment.withUnsafeBufferPointer { environmentBuffer in
            posix_spawn(&pid, path, nil, &attributes, buffer.baseAddress!, environmentBuffer.baseAddress!)
        }
    }
    if forwarding {
        if error == 0 { childPID = pid }
        sigprocmask(SIG_SETMASK, &oldMask, nil)
    }
    guard error == 0 else { diagnostic("cannot launch \(arguments[0]): \(String(cString: strerror(error)))"); return error == ENOENT ? 127 : 126 }
    var status: Int32 = 0
    while waitpid(pid, &status, 0) < 0 {
        if errno != EINTR { diagnostic("wait failed"); return 1 }
    }
    if forwarding {
        sigprocmask(SIG_BLOCK, &blocked, nil)
        childPID = 0
        sigprocmask(SIG_SETMASK, &oldMask, nil)
    }
    let sig = status & 0x7f
    return sig == 0 ? (status >> 8) & 0xff : 128 + sig
}

#if canImport(AppKit)
private final class AppOpenResult {
    private let lock = NSLock()
    private var result: Result<Void, Error>?

    func complete(_ error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        result = error.map { .failure($0) } ?? .success(())
    }

    func snapshot() -> Result<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}

private func openInOwningApp(_ url: URL, appURL: URL) -> Bool {
    let result = AppOpenResult()
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.allowsRunningApplicationSubstitution = false
    NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
        result.complete(error)
    }
    let deadline = Date().addingTimeInterval(30)
    while Date() < deadline {
        if let value = result.snapshot() {
            switch value {
            case .success: return true
            case .failure(let error): diagnostic(error.localizedDescription); return false
            }
        }
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    diagnostic("Timed out opening the matching AlwaysOn app.")
    return false
}
#endif

func send(_ action: String, query: [URLQueryItem] = []) -> Bool {
    var url = URLComponents()
    url.scheme = "alwayson"
    url.host = action
    if !query.isEmpty { url.queryItems = query }
    guard let owner = try? runningInstallation() else {
        diagnostic("Install the full AlwaysOn app and use its bundled command line tool.")
        return false
    }
    let launcher = ProcessInfo.processInfo.environment["ALWAYSON_URL_OPENER"]
    #if canImport(AppKit)
    if launcher == nil {
        return openInOwningApp(url.url!, appURL: owner.appURL)
    }
    #endif
    let status = spawnAndWait([launcher ?? "open", "-a", owner.appURL.path, url.string!])
    if status != 0 { diagnostic("\(action) transport failed (\(status))") }
    return status == 0
}

func parseDate(_ value: String) -> Date? {
    if value.range(of: #"^[0-9]{2}:[0-9]{2}$"#, options: .regularExpression) != nil {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, parts[0] < 24, parts[1] < 60 else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let date = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: today),
              calendar.isDate(date, inSameDayAs: today),
              calendar.component(.hour, from: date) == parts[0], calendar.component(.minute, from: date) == parts[1] else { return nil }
        return date
    }
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
}

let usage = """
Usage: alwayson start|stop|toggle
       alwayson timer MINUTES           (1...1440)
       alwayson pause [MINUTES]         (1...1440; omit to pause until resumed)
       alwayson until HH:MM|ISO8601      (future; HH:MM is today locally)
       alwayson run -- COMMAND [args...]
       alwayson status [--json]
       alwayson profile [NAME]          (omit NAME to list profiles)
       alwayson install [--directory PATH]
       alwayson uninstall [--directory PATH]
       alwayson version|--version
       alwayson help|--help
Prefer Settings > General > Command Line Tool to install or uninstall.
Requests require the installed macOS app and Accessibility permission.
Exit status 3 means AlwaysOn got the request but its status didn't show the result.
"""

func userHome() -> URL {
    ProcessInfo.processInfo.environment["HOME"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser
}

/// The running app's status, or nil when it isn't running or doesn't report one
func currentStatus() -> SessionStatus? {
    SessionStatus.read(from: SessionStatus.fileURL(userHome: userHome()))
}

let notRunningMessage = "AlwaysOn isn't running, or it is a version that doesn't report its status."

func runningInstallation(_ directory: String? = nil) throws -> CLIInstallation {
    guard let invoked = executable(CommandLine.arguments[0]) else { throw CLIInstallation.Failure.invalidApp }
    let owner = try CLIInstallation.owningApp(executableURL: URL(fileURLWithPath: invoked))
    let home = userHome()
    return CLIInstallation(appURL: owner.appURL, userHome: home,
                           directory: directory.map { URL(fileURLWithPath: $0) })
}
/// Polls the status file until `matches` holds or `timeout` passes.
/// Returns the matching status, or nil with the last status seen in `latest`.
func waitForStatus(timeout: TimeInterval = 2, latest: inout SessionStatus?,
                   _ matches: (SessionStatus) -> Bool) -> SessionStatus? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        latest = currentStatus()
        if let status = latest, matches(status) { return status }
        usleep(100_000)
    } while Date() < deadline
    return nil
}

/// After a `run` request, waits briefly for the app to report the command
/// session. Only meaningful when the app was already running and reporting.
func confirmCommandSession() {
    var latest: SessionStatus?
    if waitForStatus(latest: &latest, { $0.state == .active && $0.source == "command" }) != nil { return }
    if latest?.hasAccessibilityPermission == false {
        diagnostic("AlwaysOn needs Accessibility permission, so it isn't keeping you online. The command runs anyway.")
    } else {
        diagnostic("AlwaysOn didn't confirm the session. The command runs anyway.")
    }
}

/// What the app's status must show once it has applied `action`
func expectation(for action: String, query: [URLQueryItem], before: SessionStatus,
                 sentAt: Date) -> (SessionStatus) -> Bool {
    func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
    func near(_ date: Date?, _ target: Date, within seconds: TimeInterval) -> Bool {
        guard let date else { return false }
        return abs(date.timeIntervalSince(target)) <= seconds
    }
    switch action {
    case "start": return { $0.state == .active }
    case "stop": return { $0.state == .off }
    case "toggle":
        return before.state == .active ? { $0.state != .active } : { $0.state == .active }
    case "timer":
        let minutes = Double(value("minutes") ?? "") ?? 0
        let target = sentAt.addingTimeInterval(minutes * 60)
        return { $0.state == .active && $0.source == "timer" && near($0.endsAt, target, within: 5) }
    case "pause":
        guard let minutes = value("minutes").flatMap(Double.init) else { return { $0.state == .paused } }
        let target = sentAt.addingTimeInterval(minutes * 60)
        return { $0.state == .paused && near($0.resumesAt, target, within: 5) }
    case "until":
        let formatter = ISO8601DateFormatter()
        guard let date = value("date").flatMap(formatter.date(from:)) else { return { _ in false } }
        return { $0.state == .active && $0.source == "until" && near($0.endsAt, date, within: 1) }
    case "profile":
        let name = value("name") ?? ""
        return { $0.profile.compare(name, options: .caseInsensitive) == .orderedSame }
    default: return { _ in false }
    }
}

/// Sends a control request and, when the app was already reporting its
/// status, waits for the status to show the result.
/// Returns 0 when confirmed or unconfirmable, 1 on transport failure,
/// 3 when delivered but not confirmed.
func sendAndConfirm(_ action: String, query: [URLQueryItem] = []) -> Int32 {
    let before = currentStatus()
    let sentAt = Date()
    guard send(action, query: query) else { return 1 }
    guard let before else {
        print("Sent \(action) request to AlwaysOn. It wasn't running, so the result can't be confirmed yet. Check with `alwayson status`.")
        return 0
    }
    var latest: SessionStatus?
    if let status = waitForStatus(latest: &latest, expectation(for: action, query: query, before: before, sentAt: sentAt)) {
        print(status.summaryLines.first ?? "AlwaysOn applied the \(action) request.")
        return 0
    }
    if latest?.hasAccessibilityPermission == false {
        diagnostic("AlwaysOn needs Accessibility permission, so it didn't apply the \(action) request.")
    } else {
        diagnostic("AlwaysOn didn't confirm the \(action) request.")
    }
    if let line = latest?.summaryLines.first { diagnostic("Current status: \(line)") }
    return 3
}

enum CLIError: Error { case message(String) }
func main(_ args: [String]) throws -> Int32 {
    guard let action = args.first else { throw CLIError.message(usage) }
    let rest = Array(args.dropFirst())
    switch action {
    case "help", "--help":
        guard rest.isEmpty else { throw CLIError.message(usage) }
        print(usage); return 0
    case "version", "--version":
        guard rest.isEmpty else { throw CLIError.message(usage) }
        if let owner = try? runningInstallation(), let version = owner.version {
            print("AlwaysOn \(version)")
        } else { print("AlwaysOn development/unbundled (no app version)") }
        return 0
    case "install", "uninstall":
        guard rest.isEmpty || (rest.count == 2 && rest[0] == "--directory" && !rest[1].isEmpty) else { throw CLIError.message(usage) }
        let installation = try runningInstallation(rest.last)
        if action == "install" { try installation.install() } else { try installation.uninstall() }
        print("\(action == "install" ? "Installed" : "Uninstalled") \(installation.linkURL.path)")
        return 0
    case "status":
        guard rest.isEmpty || rest == ["--json"] else { throw CLIError.message(usage) }
        guard let status = currentStatus() else { diagnostic(notRunningMessage); return 1 }
        if rest.isEmpty {
            status.summaryLines.forEach { print($0) }
        } else {
            print(String(decoding: try status.encoded(), as: UTF8.self))
        }
        return 0
    case "profile":
        guard rest.count <= 1 else { throw CLIError.message(usage) }
        let status = currentStatus()
        guard let requested = rest.first else {
            guard let status else { diagnostic(notRunningMessage); return 1 }
            for name in status.profiles { print(name == status.profile ? "* \(name)" : "  \(name)") }
            return 0
        }
        let name = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CLIError.message("profile requires a profile name") }
        // With a running app the name can be checked; without one the request is sent as is
        if let status, status.profileName(matching: name) == nil {
            diagnostic("No profile named \"\(name)\". Profiles: \(status.profiles.joined(separator: ", "))")
            return 1
        }
        return sendAndConfirm(action, query: [URLQueryItem(name: "name", value: name)])
    case "start", "stop", "toggle":
        guard rest.isEmpty else { throw CLIError.message(usage) }
        return sendAndConfirm(action)
    case "timer":
        guard rest.count == 1, rest[0].range(of: #"^[0-9]+$"#, options: .regularExpression) != nil,
              let minutes = Int(rest[0]), (1...1440).contains(minutes) else { throw CLIError.message("timer requires integer minutes 1...1440") }
        return sendAndConfirm(action, query: [URLQueryItem(name: "minutes", value: String(minutes))])
    case "pause":
        guard rest.count <= 1 else { throw CLIError.message(usage) }
        var query: [URLQueryItem] = []
        if let value = rest.first {
            guard value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil,
                  let minutes = Int(value), (1...1440).contains(minutes) else { throw CLIError.message("pause requires integer minutes 1...1440, or none") }
            query = [URLQueryItem(name: "minutes", value: String(minutes))]
        }
        return sendAndConfirm(action, query: query)
    case "until":
        guard rest.count == 1, let date = parseDate(rest[0]), date.timeIntervalSince1970.isFinite, date > Date() else { throw CLIError.message("until requires a future local time today or ISO8601 datetime") }
        return sendAndConfirm(action, query: [URLQueryItem(name: "date", value: ISO8601DateFormatter().string(from: date))])
    case "run":
        guard rest.count >= 2, rest[0] == "--" else { throw CLIError.message(usage) }
        let token = [URLQueryItem(name: "token", value: UUID().uuidString)]
        // A status from before the request means the app can confirm it
        let reportsStatus = currentStatus() != nil
        guard send("run", query: token) else { return 1 }
        if reportsStatus { confirmCommandSession() }
        let previous = [SIGINT, SIGTERM, SIGHUP].map { ($0, signal($0, forwardSignal)) }
        let status = spawnAndWait(Array(rest.dropFirst()), forwarding: true)
        _ = send("finish", query: token)
        for (number, handler) in previous { signal(number, handler) }
        return status
    default: throw CLIError.message(usage)
    }
}
do { exit(try main(Array(CommandLine.arguments.dropFirst()))) }
catch CLIError.message(let message) { diagnostic(message); exit(2) }
catch { diagnostic(error.localizedDescription); exit(1) }
