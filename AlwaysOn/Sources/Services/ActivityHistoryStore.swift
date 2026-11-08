import Foundation
import Combine

/// Persists the activity ledger as a small JSON file in Application Support.
/// Writes happen only when a segment starts or ends and at sparse
/// checkpoints, never on a timer of their own.
final class ActivityHistoryStore: ObservableObject {
    @Published private(set) var ledger: ActivityLedger

    /// Minimum spacing of checkpoint writes while a segment is open
    static let checkpointInterval: TimeInterval = 5 * 60

    private let fileURL: URL?
    private var lastCheckpointWrite: Date?

    /// - Parameter fileURL: Where to keep history; nil keeps it in memory only
    init(fileURL: URL? = ActivityHistoryStore.defaultFileURL, now: Date = Date()) {
        self.fileURL = fileURL
        let loaded = fileURL.flatMap(Self.load) ?? ActivityLedger()
        var ledger = loaded
        ledger.recoverAfterRelaunch()
        ledger.prune(now: now)
        self.ledger = ledger
        if ledger != loaded { save() }
    }

    static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AlwaysOn", isDirectory: true)
            .appendingPathComponent("activity-history.json")
    }

    /// Records whether the user is being kept online right now, and by what kind of session
    func update(isOnline: Bool, kind: SessionKind, now: Date = Date()) {
        var next = ledger
        guard next.update(isOnline: isOnline, kind: kind, now: now) else { return }
        ledger = next
        lastCheckpointWrite = now
        save()
    }

    /// Notes that the open segment is still running. Cheap to call often:
    /// it writes at most once per checkpoint interval.
    func checkpoint(now: Date = Date()) {
        guard ledger.isRecording else { return }
        if let last = lastCheckpointWrite, now.timeIntervalSince(last) < Self.checkpointInterval { return }
        ledger.checkpoint(at: now)
        lastCheckpointWrite = now
        save()
    }

    /// Closes the open segment, e.g. when the app quits
    func closeOpenSegment(now: Date = Date()) {
        var next = ledger
        guard next.close(at: now) || ledger.isRecording else { return }
        ledger = next
        save()
    }

    /// Removes all recorded history; a running segment restarts from now
    func clear(now: Date = Date()) {
        let open = ledger.open
        var next = ActivityLedger()
        if let open { next.update(isOnline: true, kind: open.kind, now: now) }
        ledger = next
        save()
    }

    // MARK: - Files

    private static func load(from url: URL) -> ActivityLedger? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ActivityLedger.self, from: data)
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(ledger).write(to: fileURL, options: .atomic)
        } catch {
            #if DEBUG
            print("[ActivityHistoryStore] Save failed: \(error)")
            #endif
        }
    }
}
