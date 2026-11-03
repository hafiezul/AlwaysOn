import Foundation

@main
struct LifecycleChecks {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let app = root.appendingPathComponent("Always On.app")
        let helper = app.appendingPathComponent("Contents/Helpers/alwayson")
        try fm.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("executable fixture".utf8).write(to: helper)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.alwayson.app", "CFBundleShortVersionString": "3.0", "CFBundleVersion": "12"], format: .xml, options: 0)
        try info.write(to: app.appendingPathComponent("Contents/Info.plist"))
        let lifecycle = CLIInstallation(appURL: app, userHome: root)
        precondition(lifecycle.status == .absent)
        precondition(!lifecycle.canUninstall)
        precondition(lifecycle.version == "3.0 (12)")
        try lifecycle.install()
        precondition(lifecycle.status == .current)
        precondition(lifecycle.canUninstall)
        try lifecycle.install()
        try fm.removeItem(at: helper)
        precondition(lifecycle.status == .missingBundledCLI)
        precondition(lifecycle.canUninstall)
        try lifecycle.uninstall()
        precondition((try? fm.destinationOfSymbolicLink(atPath: lifecycle.linkURL.path)) == nil)
        precondition(!lifecycle.canUninstall)
        try Data("restored executable".utf8).write(to: helper)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        precondition(lifecycle.status == .absent)
        precondition(!lifecycle.canUninstall)
        try lifecycle.install()
        try lifecycle.uninstall()
        try lifecycle.uninstall()
        try Data("user tool".utf8).write(to: lifecycle.linkURL)
        precondition(lifecycle.status == .conflict)
        precondition(!lifecycle.canUninstall)
        do { try lifecycle.install(); preconditionFailure("overwrote user file") }
        catch CLIInstallation.Failure.conflict { }
        do { try lifecycle.uninstall(); preconditionFailure("deleted user file") }
        catch CLIInstallation.Failure.conflict { }
        let preserved = try String(contentsOf: lifecycle.linkURL)
        precondition(preserved == "user tool")
        try fm.removeItem(at: lifecycle.linkURL)
        let otherApp = root.appendingPathComponent("Other AlwaysOn.app")
        try fm.copyItem(at: app, to: otherApp)
        let other = CLIInstallation(appURL: otherApp, userHome: root)
        try other.install()
        guard case .anotherApp(let owner) = lifecycle.status else {
            preconditionFailure("expected another app link")
        }
        precondition(owner.path == other.appURL.path)
        precondition(!lifecycle.canUninstall)
        try fm.removeItem(at: helper)
        precondition(lifecycle.status == .missingBundledCLI)
        precondition(!lifecycle.canUninstall)
        try other.uninstall()
        try fm.createSymbolicLink(at: lifecycle.linkURL, withDestinationURL: root.appendingPathComponent("unrelated-missing-tool"))
        precondition(!lifecycle.canUninstall)
        print("Lifecycle status, missing-helper owned unlink, idempotence and conflict checks passed")
    }
}
