import Foundation
import Combine
import AppKit
import CoreGraphics
import Darwin

@main
struct OptimizationBenchmark {
    static func cpu() -> Double {
        var usage = rusage()
        precondition(getrusage(RUSAGE_SELF, &usage) == 0)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    @MainActor
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 4, let iterations = Int(args[2]), iterations > 0,
              let expectedQueries = Int(args[3]) else { exit(2) }
        let scenario = args[1]
        let suite = "AlwaysOn.benchmark.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let profiles = (0..<5).map { index in
            Profile(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012ld", index + 1))!,
                    name: "Fake \(index)", activityInterval: Double(45 + index),
                    activityMethodId: "mouse", defaultTimerDurationId: "none", workSchedule: .default)
        }
        defaults.set(ProfileManager.encodeProfiles(profiles), forKey: "alwayson.profiles")
        defaults.set(profiles[0].id.uuidString, forKey: "alwayson.activeProfileId")
        let manager = ProfileManager(defaults: defaults)
        let gate = ActivityGate()
        var idleQueries = 0
        var targetQueries = 0
        var checksum = 0
        var failures: [String] = []
        func idle() -> TimeInterval {
            idleQueries += 1
            return CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                           eventType: CGEventType(rawValue: ~0)!)
        }
        func target() -> Bool {
            targetQueries += 1
            return NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier.map(gate.targetBundleIDs.contains) ?? false
            }
        }
        let startCPU = cpu()
        let startWall = DispatchTime.now().uptimeNanoseconds
        switch scenario {
        case "disabled-gates":
            for _ in 0..<iterations {
                if gate.shouldPost(idleSeconds: idle(), hasRunningTarget: target()) { checksum += 1 }
            }
        case "identical-profile-settings":
            let p = profiles[0]
            for _ in 0..<iterations {
                manager.updateProfileSettings(p.id, activityInterval: p.activityInterval,
                    activityMethod: p.activityMethod, defaultTimerDuration: p.defaultTimerDuration,
                    workSchedule: p.workSchedule)
                checksum += 1
            }
        case "profile-switch":
            for index in 0..<iterations {
                let p = profiles[(index + 1) % 2]
                if manager.switchProfile(to: p.id)?.id == p.id { checksum += 1 }
            }
        case "unchanged-profile-rename":
            for _ in 0..<iterations {
                manager.renameProfile(profiles[0].id, to: profiles[0].name)
                checksum += 1
            }
        default: exit(2)
        }
        let wall = Double(DispatchTime.now().uptimeNanoseconds - startWall) / 1_000_000_000
        let elapsedCPU = cpu() - startCPU
        let expectedID = scenario == "profile-switch" ? profiles[iterations % 2].id : profiles[0].id
        if checksum != iterations { failures.append("checksum") }
        if idleQueries != expectedQueries || targetQueries != expectedQueries { failures.append("provider counts") }
        if manager.profiles != profiles || manager.activeProfile != profiles.first(where: { $0.id == expectedID }) {
            failures.append("in-memory settings/identity")
        }
        if ProfileManager.loadProfiles(from: defaults) != profiles { failures.append("stored settings") }
        if defaults.string(forKey: "alwayson.activeProfileId") != expectedID.uuidString { failures.append("stored identity") }
        let reloaded = ProfileManager(defaults: defaults)
        if reloaded.profiles != profiles || reloaded.activeProfileId != expectedID { failures.append("reload") }
        let output: [String: Any] = ["scenario": scenario, "iterations": iterations,
            "cpu_seconds": elapsedCPU, "wall_seconds": wall, "checksum": checksum,
            "idle_queries": idleQueries, "target_queries": targetQueries, "failures": failures,
            "active_profile_id": manager.activeProfileId.uuidString, "profile_count": manager.profiles.count]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
        if !failures.isEmpty { exit(1) }
    }
}
