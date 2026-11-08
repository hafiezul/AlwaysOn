import Charts
import SwiftUI

/// Online time per day for the last week, from the history kept on this Mac
struct ActivitySettingsPane: View {
    @ObservedObject var history: ActivityHistoryStore
    @State private var confirmingClear = false

    private static let chartDays = 7

    var body: some View {
        // Refresh once a minute so a running session's total keeps up while the pane is open
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let days = history.ledger.daily(days: Self.chartDays, now: now)
        let today = days.last?.total ?? 0
        let week = days.reduce(0) { $0 + $1.total }
        let activeDays = days.filter { $0.total > 0 }

        return Form {
            Section {
                HStack(alignment: .top, spacing: 24) {
                    summaryTile("Today", ActivityDurationFormat.long(today))
                    summaryTile("Last 7 days", ActivityDurationFormat.long(week))
                    summaryTile("Daily average",
                                ActivityDurationFormat.long(activeDays.isEmpty ? 0 : week / Double(activeDays.count)))
                }
                .padding(.vertical, 4)

                if week > 0 {
                    chart(days)
                        .frame(height: 180)
                        .padding(.vertical, 4)
                } else {
                    Text("No sessions in the last 7 days. Online time appears here once you keep online.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .multilineTextAlignment(.center)
                }
            } header: {
                Text("Online Time")
            } footer: {
                Text("Counts time a session was active while the Mac was awake. Time paused for sleep or a locked screen isn't counted.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    Text("History stays on this Mac and keeps the last \(ActivityLedger.retentionDays) days.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear History…", role: .destructive) { confirmingClear = true }
                        .disabled(history.ledger.segments.isEmpty && !history.ledger.isRecording)
                }
            } header: {
                Text("Privacy")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear all activity history?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { history.clear() }
        } message: {
            Text("This removes every recorded day. A running session keeps counting from now.")
        }
    }

    private func summaryTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Kinds that appear in the chart, in a fixed order so colors never shuffle
    private func presentKinds(_ days: [DailyActivity]) -> [SessionKind] {
        SessionKind.allCases.filter { kind in days.contains { ($0.byKind[kind] ?? 0) > 0 } }
    }

    private func chart(_ days: [DailyActivity]) -> some View {
        Chart {
            ForEach(days) { day in
                ForEach(SessionKind.allCases) { kind in
                    if let seconds = day.byKind[kind], seconds > 0 {
                        BarMark(
                            x: .value("Day", day.day, unit: .day),
                            y: .value("Hours", seconds / 3600)
                        )
                        .foregroundStyle(by: .value("Started by", kind.title))
                        .accessibilityLabel(day.day.formatted(.dateTime.weekday(.wide)))
                        .accessibilityValue("\(kind.title): \(ActivityDurationFormat.long(seconds))")
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) { Text("\(hours, specifier: "%.0f")h") }
                }
            }
        }
        .chartForegroundStyleScale(domain: presentKinds(days).map(\.title),
                                   range: presentKinds(days).map(\.chartColor))
        .chartLegend(position: .bottom, alignment: .leading)
    }
}

extension SessionKind {
    /// One stable color per kind across the chart and legend
    var chartColor: Color {
        switch self {
        case .schedule: return .blue
        case .timer: return .green
        case .until: return .orange
        case .manual: return .purple
        case .command: return .teal
        case .focus: return .indigo
        }
    }
}
