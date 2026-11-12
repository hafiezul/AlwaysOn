import SwiftUI

/// Lists workdays the calendar shows the user is out, and adds only the ones they tick
struct CalendarDaysOffSheet: View {
    let schedule: WorkSchedule
    let onAdd: ([Date]) -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var calendar = CalendarEventProvider()
    /// Nil while loading
    @State private var suggestions: [DayOffSuggestion]?
    @State private var selected: Set<String> = []
    @State private var denied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Days Off from Calendar")
                .font(.title3.weight(.semibold))
            Text("Workdays in the next 60 days whose work hours are fully covered by an out-of-office event or an all-day event. Choose which to add. AlwaysOn saves only the dates.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            content

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(selected.isEmpty ? "Add Days Off" : "Add \(selected.count) Day\(selected.count == 1 ? "" : "s") Off") {
                    onAdd(suggestions?.filter { selected.contains($0.id) }.map(\.date) ?? [])
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .task {
            if let blocks = await calendar.loadDayOffBlocks() {
                let found = CalendarDaysOff.suggestions(from: blocks, schedule: schedule, from: Date())
                suggestions = found
                selected = Set(found.filter(\.isOutOfOffice).map(\.id))
            } else {
                denied = true
                suggestions = []
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let suggestions {
            if denied {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AlwaysOn can't read your calendars.")
                    if calendar.accessState == .writeOnly {
                        Text("Choose Full Access for AlwaysOn in System Settings > Privacy & Security > Calendars.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button("Open Calendar Settings") { CalendarEventProvider.openCalendarSettings() }
                }
            } else if suggestions.isEmpty {
                Text("No out-of-office or all-day events cover your work hours in the next 60 days.")
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(suggestions) { suggestion in
                            Toggle(isOn: binding(for: suggestion.id)) {
                                VStack(alignment: .leading) {
                                    Text(suggestion.date.formatted(date: .complete, time: .omitted))
                                    Text((suggestion.isOutOfOffice ? "Out of office: " : "All-day: ") + suggestion.reason)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
            }
        } else {
            ProgressView()
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { isOn in
                if isOn { selected.insert(id) } else { selected.remove(id) }
            }
        )
    }
}
