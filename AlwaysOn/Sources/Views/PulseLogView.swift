import SwiftUI

/// Live, memory-only record of AlwaysOn's own input attempts: totals by
/// category, a timeline of recent attempts, and a filterable list that says
/// why each one happened. Observes the log directly so entries appear live.
struct PulseLogView: View {
    @ObservedObject var pulseLog: PulseLog
    @State private var filter: PulseLog.Category?

    /// Newest entries shown; older ones are still counted
    private static let visibleLimit = 200
    private static let timelineCount = 60

    private var visibleEntries: [PulseLog.Entry] {
        let recent = pulseLog.history.suffix(Self.visibleLimit).reversed()
        guard let filter else { return Array(recent) }
        return recent.filter { $0.outcome.category == filter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            tiles
            timeline
            filterBar
            entries
            Text("Kept in memory only and cleared when AlwaysOn quits. Totals count since launch or the last clear.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 560)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pulse Log")
                    .font(.title2.weight(.bold))
                Text("Each time AlwaysOn tries to send input. It can't see your Teams or Slack status.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Clear Log", role: .destructive) { pulseLog.clear() }
                .buttonStyle(ActionButtonStyle(compact: true))
                .disabled(pulseLog.history.isEmpty)
        }
    }

    private var tiles: some View {
        HStack(spacing: 10) {
            ForEach(PulseLog.Category.allCases) { category in
                tile(category)
            }
        }
    }

    private func tile(_ category: PulseLog.Category) -> some View {
        let count = pulseLog.count(of: category)
        return VStack(alignment: .leading, spacing: 6) {
            Image(systemName: category.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(category.tint)
            Text("\(count)")
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundColor(count == 0 ? .secondary : .primary)
            Text(category.title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .accessibilityElement(children: .combine)
    }

    private var timeline: some View {
        let recent = Array(pulseLog.history.suffix(Self.timelineCount))
        return VStack(alignment: .leading, spacing: 6) {
            Text("Last \(Self.timelineCount) attempts")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            GeometryReader { proxy in
                let spacing: CGFloat = 2
                let width = max((proxy.size.width - spacing * CGFloat(Self.timelineCount - 1)) / CGFloat(Self.timelineCount), 2)
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(0..<(Self.timelineCount - recent.count), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.primary.opacity(0.07))
                            .frame(width: width, height: 26)
                    }
                    ForEach(recent) { entry in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(entry.outcome.tint.opacity(entry.outcome == .posted ? 0.85 : 0.65))
                            .frame(width: width, height: entry.outcome == .posted ? 26 : 14)
                            .help("\(entry.summary) · \(entry.date.formatted(date: .omitted, time: .standard))")
                    }
                }
                .frame(height: 26, alignment: .bottom)
            }
            .frame(height: 26)
            HStack {
                Text(recent.first.map { $0.date.formatted(date: .omitted, time: .shortened) } ?? "")
                Spacer()
                Text(recent.last.map { "Latest \($0.date.formatted(date: .omitted, time: .shortened))" } ?? "No attempts yet")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .monospacedDigit()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timeline of the last \(recent.count) attempts")
    }

    private var filterBar: some View {
        Picker("Show", selection: $filter) {
            Text("All").tag(PulseLog.Category?.none)
            ForEach(PulseLog.Category.allCases) { category in
                Text(category.title).tag(PulseLog.Category?.some(category))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var entries: some View {
        if visibleEntries.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: filter?.symbol ?? "waveform.path.ecg")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text(filter.map { "No \($0.title.lowercased()) attempts" } ?? "No input attempts yet")
                    .font(.headline)
                Text(filter == nil
                     ? "Start a session. Each attempt, including skipped ones, appears here as it happens."
                     : "Choose All to see every attempt.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(visibleEntries) { entry in
                PulseEntryRow(entry: entry)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(maxHeight: .infinity)
        }
    }
}

/// One recorded attempt: what happened, why, and when
private struct PulseEntryRow: View {
    let entry: PulseLog.Entry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: entry.outcome.symbol)
                .foregroundColor(entry.outcome.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.summary)
                Text(entry.outcome.explanation)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(entry.date.formatted(date: .omitted, time: .standard))
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

extension PulseLog.Category {
    var symbol: String {
        switch self {
        case .posted: return "checkmark.circle.fill"
        case .skipped: return "hand.raised.fill"
        case .paused: return "moon.zzz.fill"
        case .problem: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .posted: return .green
        case .skipped: return .orange
        case .paused: return .indigo
        case .problem: return .red
        }
    }
}
