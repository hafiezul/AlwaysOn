import AppKit
import SwiftUI

/// Renders AlwaysOn's real views offscreen into the README screenshots.
/// Nothing is put on screen and nothing is captured from it: each view draws
/// itself into a bitmap through `cacheDisplay`. Built and run by render.sh.
///
/// To add a screenshot, stage any data it needs in `run`, add a render call in
/// `renderAll`, and reference both PNGs from the README with a `<picture>` tag.
@main
struct ShotsMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let dark = CommandLine.arguments.contains("--dark")
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { Shots.run(suffix: dark ? "-dark" : "") }
        }
        app.run()
    }
}

@MainActor
enum Shots {
    static let environment = ProcessInfo.processInfo.environment
    static let out = URL(fileURLWithPath: environment["ALWAYSON_SHOTS_OUT"] ?? "screenshots")
    static let historyFile = URL(fileURLWithPath: environment["ALWAYSON_SHOTS_HISTORY"] ?? "activity-history.json")
    static var keep: [NSWindow] = []
    static var appState: AppState!

    static func run(suffix: String) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        // Start from empty settings every run, so earlier runs can't leak in
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        writeHistory()

        let state = AppState()
        appState = state
        state.profileManager.renameProfile(state.profileManager.activeProfileId, to: "Work")

        // A 2-hour timer that started 47 minutes ago
        state.startWithQuickTimer(.custom(minutes: 120))
        let now = Date()
        state.quickTimerEndTime = now.addingTimeInterval(73 * 60)
        state.timerStartedAt = now.addingTimeInterval(-47 * 60)
        state.quickTimerRemaining = 73 * 60
        state.activeSessionDuration = 47 * 60

        stagePulseLog(state.pulseLog, now: now)

        // Let Combine pipelines and the history debounce settle before drawing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            MainActor.assumeIsolated {
                renderAll(suffix: suffix)
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Sample data

    /// A believable week: work hours on weekdays plus a few other session kinds
    static func writeHistory() {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        var ledger = ActivityLedger()
        func add(_ start: Date, _ end: Date, _ kind: SessionKind) {
            guard end > start, end <= now else { return }
            _ = ledger.update(isOnline: true, kind: kind, now: start)
            _ = ledger.update(isOnline: false, kind: kind, now: end)
        }
        func at(_ day: Date, _ hours: Double) -> Date { day.addingTimeInterval(hours * 3600) }

        for offset in stride(from: 6, through: 1, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekday = cal.component(.weekday, from: day)
            if weekday == 1 || weekday == 7 {
                if offset % 2 == 0 { add(at(day, 10.5), at(day, 11.25), .timer) }
                continue
            }
            add(at(day, 9), at(day, 12.5), .schedule)
            add(at(day, 13.25), at(day, 17), .schedule)
            switch offset % 3 {
            case 0: add(at(day, 17), at(day, 17.75), .until)
            case 1: add(at(day, 19.5), at(day, 20.4), .command)
            default: add(at(day, 8.25), at(day, 9), .focus)
            }
        }
        // Today: earlier sessions that ended before the current timer began
        add(now.addingTimeInterval(-4.5 * 3600), now.addingTimeInterval(-2 * 3600), .schedule)
        add(now.addingTimeInterval(-1.6 * 3600), now.addingTimeInterval(-1.1 * 3600), .until)

        try? JSONEncoder().encode(ledger).write(to: historyFile, options: .atomic)
    }

    /// One attempt every 45 seconds over the last 47 minutes, with stretches
    /// skipped while the user types and a short pause for a locked screen
    static func stagePulseLog(_ log: PulseLog, now: Date) {
        for i in stride(from: 62, through: 1, by: -1) {
            let outcome: PulseLog.Outcome
            switch i {
            case 50...62, 1...12: outcome = .posted
            case 30...49: outcome = (i % 5 == 0) ? .posted : .userActive
            case 24...29: outcome = .systemPaused
            default: outcome = (i % 3 == 0) ? .userActive : .posted
            }
            log.record(outcome, date: now.addingTimeInterval(-Double(i) * 45))
        }
    }

    // MARK: - Rendering

    static func renderAll(suffix: String) {
        renderMenu(name: "menu\(suffix)")
        renderWindow(PulseLogView(pulseLog: appState.pulseLog), title: "Pulse Log",
                     size: NSSize(width: 580, height: 680), name: "pulse-log\(suffix)")
        renderWindow(UntilSessionView(onClose: {}).environmentObject(appState), title: "Keep Online Until",
                     size: NSSize(width: 480, height: 540), name: "keep-online-until\(suffix)")
        // The Settings sidebar is Liquid Glass, which only the window server can
        // draw, so the Activity pane renders in a window of its own
        renderWindow(ActivitySettingsPane(history: appState.activityHistory), title: "Activity",
                     size: NSSize(width: 600, height: 560), name: "settings-activity\(suffix)")
    }

    /// The menu bar panel, on a solid background in place of the menu material
    static func renderMenu(name: String) {
        let panel = MenuBarView()
            .environmentObject(appState)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        let host = NSHostingView(rootView: panel)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        keep.append(window)
        write(view: host, name: name)
    }

    /// A titled window, drawn with its title bar but never ordered on screen
    static func renderWindow<V: View>(_ view: V, title: String, size: NSSize, name: String) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.contentView = host
        window.setContentSize(size)
        keep.append(window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        write(view: host.superview ?? host, name: name, cornerRadius: 12)
    }

    /// Clips a window bitmap to rounded corners and draws a hairline border
    static func rounded(_ rep: NSBitmapImageRep, radius: CGFloat, appearance: NSAppearance) -> NSBitmapImageRep {
        let size = rep.size
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return rep }
        out.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
        path.addClip()
        rep.draw(in: rect)
        appearance.performAsCurrentDrawingAppearance {
            NSColor.separatorColor.setStroke()
        }
        path.lineWidth = 0.5
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
        return out
    }

    /// Draws a view into a 2x bitmap and writes it as a PNG
    static func write(view: NSView, name: String, cornerRadius: CGFloat = 0) {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bounds = view.bounds
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        let final = cornerRadius > 0 ? rounded(rep, radius: cornerRadius, appearance: view.effectiveAppearance) : rep
        guard let data = final.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: out.appendingPathComponent("\(name).png"))
        print("wrote screenshots/\(name).png (\(Int(bounds.width))x\(Int(bounds.height)) pt)")
    }
}
