import SwiftUI

/// The top of the menu: whether AlwaysOn is keeping you online, for how long,
/// and what started it
struct SessionStatusCard: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        StatusCardContent(model: .init(appState: appState))
    }
}

/// Everything the status card shows, as plain values
struct StatusCardModel {
    enum Phase { case off, active, paused }

    var phase: Phase
    /// Seconds left for a timed session, seconds elapsed otherwise
    var seconds: TimeInterval
    var isTimed: Bool
    /// How much of a timed session remains, 0...1
    var remainingFraction: Double?
    var detail: String?
    var today: TimeInterval
    /// Elapsed time of the current session, to tell whether today's total adds anything
    var sessionElapsed: TimeInterval = 0
    var isSuspended: Bool

    /// Today's total is worth showing when AlwaysOn is off, or when earlier
    /// sessions today make it differ from the current session's elapsed time
    var showsTodayTotal: Bool {
        guard today >= 60 else { return false }
        return phase == .off || today - sessionElapsed >= 60
    }

    @MainActor
    init(appState: AppState) {
        phase = appState.isActive ? .active : (appState.hasActiveOrPausedSession ? .paused : .off)
        isTimed = appState.sessionDeadline != nil
        seconds = isTimed ? appState.quickTimerRemaining : appState.activeSessionDuration
        remainingFraction = appState.sessionProgress.map { 1 - $0 }
        today = appState.onlineTimeToday
        sessionElapsed = appState.activeSessionDuration
        isSuspended = appState.systemSuspension != nil
        detail = Self.detail(label: appState.sessionSourceLabel, deadline: appState.sessionDeadline,
                             isOff: phase == .off)
    }

    init(phase: Phase, seconds: TimeInterval, isTimed: Bool, remainingFraction: Double?,
         detail: String?, today: TimeInterval, isSuspended: Bool = false) {
        self.phase = phase
        self.seconds = seconds
        self.isTimed = isTimed
        self.remainingFraction = remainingFraction
        self.detail = detail
        self.today = today
        self.isSuspended = isSuspended
    }

    /// "Until · Standup · ends 5:30 PM", capitalized
    static func detail(label: String?, deadline: Date?, isOff: Bool, now: Date = Date()) -> String? {
        guard !isOff else { return nil }
        var parts: [String] = []
        if let label { parts.append(label) }
        if let deadline {
            let style: Date.FormatStyle.DateStyle = Calendar.current.isDate(deadline, inSameDayAs: now) ? .omitted : .abbreviated
            parts.append("ends \(deadline.formatted(date: style, time: .shortened))")
        }
        guard !parts.isEmpty else { return nil }
        let line = parts.joined(separator: " · ")
        return line.prefix(1).uppercased() + line.dropFirst()
    }
}

struct StatusCardContent: View {
    let model: StatusCardModel

    private var tint: Color {
        switch model.phase {
        case .off: return .secondary
        case .active: return .green
        case .paused: return .orange
        }
    }

    private var title: String {
        switch model.phase {
        case .off: return "Off"
        case .active: return "Active"
        case .paused: return "Paused"
        }
    }

    private var ringProgress: Double {
        // An unlimited session shows a full ring; a timed one empties as it runs
        model.phase == .off ? 0 : (model.remainingFraction ?? 1)
    }

    private var ringSymbol: String {
        switch model.phase {
        case .off: return "power"
        case .active: return model.isSuspended ? "moon.zzz.fill" : "dot.radiowaves.left.and.right"
        case .paused: return "pause.fill"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            StatusRing(progress: ringProgress, tint: tint, symbol: ringSymbol)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)
                    Spacer(minLength: 8)
                    if model.showsTodayTotal {
                        Text("\(ActivityDurationFormat.long(model.today)) online today")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                            .help("Total time AlwaysOn kept you online today, across all sessions")
                    }
                }

                if model.phase == .off {
                    Text("Not keeping you online")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Self.clock(model.seconds))
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                        Text(model.isTimed ? "left" : "elapsed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let detail = model.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .accessibilityElement(children: .combine)
    }

    /// 1:02:13 or 41:12
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

/// A small ring that empties as a timed session runs out
struct StatusRing: View {
    let progress: Double
    let tint: Color
    let symbol: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Each heartbeat moves the ring a little; glide between ticks
                .animation(reduceMotion ? nil : .linear(duration: 0.9), value: progress)
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}
