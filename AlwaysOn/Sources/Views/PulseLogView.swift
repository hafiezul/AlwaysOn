import SwiftUI

/// Live, memory-only record of AlwaysOn's own input attempts.
/// Observes the log directly so new entries show up without reopening the window.
struct PulseLogView: View {
    @ObservedObject var pulseLog: PulseLog

    /// Newest entries shown; older ones are still counted
    private static let visibleLimit = 200

    private var recentEntries: [PulseLog.Entry] {
        Array(pulseLog.history.suffix(Self.visibleLimit).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Records AlwaysOn input attempts; it does not read Teams or Slack status.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            latestSummary

            countsRow

            Divider()

            if pulseLog.history.isEmpty {
                emptyState
            } else {
                entryList
            }

            HStack {
                Text("Kept in memory only. Cleared when AlwaysOn quits.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Clear Log", role: .destructive) {
                    pulseLog.clear()
                }
                .disabled(pulseLog.history.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 400)
    }

    // MARK: - Sections

    @ViewBuilder
    private var latestSummary: some View {
        if let latest = pulseLog.history.last {
            VStack(alignment: .leading, spacing: 2) {
                Text("Latest")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(latest.summary)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(latest.date.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var countsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Since launch or last clear")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 14) {
                countLabel("Posted", pulseLog.counts[.posted, default: 0], symbol: "checkmark.circle", color: .green)
                countLabel("User active", pulseLog.counts[.userActive, default: 0], symbol: "hand.raised", color: .orange)
                countLabel("No target", pulseLog.counts[.noTarget, default: 0], symbol: "app.dashed", color: .secondary)
                countLabel("Failed", pulseLog.counts[.inputCreationFailed, default: 0], symbol: "xmark.octagon", color: .red)
            }
        }
    }

    private func countLabel(_ title: String, _ count: Int, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("\(count)", systemImage: symbol)
                .font(.headline)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "waveform.path.ecg")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No input attempts yet")
                .font(.headline)
            Text("Start a session. Each attempt, including skipped ones, appears here as it happens.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var entryList: some View {
        List(recentEntries, id: \.id) { entry in
            PulseEntryRow(entry: entry)
        }
        .frame(maxHeight: .infinity)
    }
}

/// One recorded input attempt
private struct PulseEntryRow: View {
    let entry: PulseLog.Entry

    /// One label, symbol and color per outcome
    private var style: (title: String, symbol: String, color: Color) {
        switch entry.outcome {
        case .posted:
            return ("Posted", "checkmark.circle", .green)
        case .userActive:
            return ("Skipped", "hand.raised", .orange)
        case .noTarget:
            return ("Skipped", "app.dashed", .secondary)
        case .inputCreationFailed:
            return ("Failed", "xmark.octagon", .red)
        case .systemPaused:
            return ("Paused", "moon.zzz", .secondary)
        case .permissionMissing:
            return ("Stopped", "lock.slash", .red)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: style.symbol)
                .foregroundColor(style.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.summary)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(style.title) · \(entry.date.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
