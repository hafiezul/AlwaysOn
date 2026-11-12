import SwiftUI

/// Settings pane for schedule automation
struct SmartFeaturesSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @State private var newDayOff = Calendar.current.startOfDay(for: Date())
    @State private var showingCalendarDaysOff = false

    private var schedule: WorkSchedule { appState.workScheduleManager.schedule }

    /// Edits the schedule in one assignment, so it publishes and saves once
    private func updateSchedule(_ change: (inout WorkSchedule) -> Void) {
        var next = appState.workScheduleManager.schedule
        change(&next)
        appState.workScheduleManager.schedule = next
    }
    
    var body: some View {
        Form {
            // Work Schedule Section
            Section {
                Toggle("Enable Work Hours Schedule", isOn: workScheduleEnabledBinding)
                
                if appState.workScheduleManager.schedule.isEnabled {
                    // Time pickers
                    HStack {
                        Text("Start Time")
                        Spacer()
                        DatePicker("", selection: startTimeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 100)
                    }
                    
                    HStack {
                        Text("End Time")
                        Spacer()
                        DatePicker("", selection: endTimeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 100)
                    }
                    
                    // Day selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Active Days")
                            .font(.subheadline)
                        
                        HStack(spacing: 4) {
                            ForEach(DayOfWeek.workWeekOrder) { day in
                                DayToggleButton(
                                    day: day,
                                    isSelected: appState.workScheduleManager.schedule.activeDays.contains(day.rawValue),
                                    action: {
                                        appState.workScheduleManager.schedule.toggleDay(day.rawValue)
                                    }
                                )
                            }
                        }
                    }
                    
                    Text("Start and end apply to every active day unless the day has its own hours below.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Label("Work Hours Schedule", systemImage: "calendar.badge.clock")
            }

            if schedule.isEnabled {
                perDayHoursSection
                breakSection
                daysOffSection
            }

            Section {
                if schedule.isEnabled {
                    // Status; the schedule only publishes at start and end, so
                    // refresh the countdown text each minute while the pane is open
                    TimelineView(.everyMinute) { _ in
                        HStack {
                            Image(systemName: appState.workScheduleManager.isWithinSchedule ? "clock.fill" : "clock")
                                .foregroundColor(appState.workScheduleManager.isWithinSchedule ? .green : .secondary)
                            Text(appState.workScheduleManager.statusDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                }
                
                Text("Automatically enable AlwaysOn during your work hours. Manual starts and stops always win, and schedule end only stops schedule-started sessions. Turn on notifications in General to hear when work hours start and end.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Status")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Per-day hours

    private var perDayHoursSection: some View {
        Section {
            ForEach(DayOfWeek.workWeekOrder.filter { schedule.activeDays.contains($0.rawValue) }) { day in
                let weekday = day.rawValue
                let hasOwn = schedule.hasCustomHours(forWeekday: weekday)
                // Day, then its hours, then the switch at the trailing edge, so
                // every row lines up whatever the day name's length
                HStack {
                    Text(day.name)
                    Spacer()
                    if hasOwn {
                        DatePicker("", selection: dayHoursBinding(weekday, start: true), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Text("–").foregroundColor(.secondary)
                        DatePicker("", selection: dayHoursBinding(weekday, start: false), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    } else {
                        Text(schedule.hours(forWeekday: weekday).formatted)
                            .foregroundColor(.secondary)
                    }
                    Toggle("Own hours for \(day.name)", isOn: Binding(
                        get: { schedule.hasCustomHours(forWeekday: weekday) },
                        set: { own in
                            updateSchedule { $0.setHours(own ? $0.hours(forWeekday: weekday) : nil, forWeekday: weekday) }
                        }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .help("Give \(day.name) its own hours")
                }
            }
            Text("Turn on a day's switch to give it its own hours, such as a shorter Friday.")
                .font(.caption)
                .foregroundColor(.secondary)
        } header: {
            Text("Hours by Day")
        }
    }

    private func dayHoursBinding(_ weekday: Int, start: Bool) -> Binding<Date> {
        minutesBinding(
            get: {
                let hours = schedule.hours(forWeekday: weekday)
                return start ? hours.startMinutes : hours.endMinutes
            },
            set: { minutes in
                updateSchedule { schedule in
                    var hours = schedule.hours(forWeekday: weekday)
                    if start {
                        hours.startMinutes = minutes
                        hours.endMinutes = max(hours.endMinutes, minutes + 1)
                    } else {
                        hours.endMinutes = minutes
                        hours.startMinutes = min(hours.startMinutes, minutes - 1)
                    }
                    schedule.setHours(hours, forWeekday: weekday)
                }
            })
    }

    // MARK: - Break

    private var breakSection: some View {
        Section {
            Toggle("Daily break", isOn: Binding(
                get: { schedule.breakTime != nil },
                set: { on in
                    updateSchedule { $0.breakTime = on ? MinuteRange(startMinutes: 12 * 60, endMinutes: 13 * 60) : nil }
                }))
            if schedule.breakTime != nil {
                HStack {
                    Text("From")
                    Spacer()
                    DatePicker("", selection: breakBinding(start: true), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("to").foregroundColor(.secondary)
                    DatePicker("", selection: breakBinding(start: false), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
            Text("Work hours pause during the break: a session they started stops, and starts again when the break ends.")
                .font(.caption)
                .foregroundColor(.secondary)
        } header: {
            Text("Break")
        }
    }

    private func breakBinding(start: Bool) -> Binding<Date> {
        minutesBinding(
            get: {
                guard let range = schedule.breakTime else { return start ? 720 : 780 }
                return start ? range.startMinutes : range.endMinutes
            },
            set: { minutes in
                updateSchedule { schedule in
                    var range = schedule.breakTime ?? MinuteRange(startMinutes: 720, endMinutes: 780)
                    if start {
                        range.startMinutes = minutes
                        range.endMinutes = max(range.endMinutes, minutes + 1)
                    } else {
                        range.endMinutes = minutes
                        range.startMinutes = min(range.startMinutes, minutes - 1)
                    }
                    schedule.breakTime = range.validated
                }
            })
    }

    // MARK: - Days off

    /// Skipped days from today on, soonest first
    private var upcomingDaysOff: [(key: String, date: Date)] {
        let today = WorkSchedule.dayKey(for: Date())
        let parser = DateFormatter()
        parser.calendar = Calendar.current
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        return schedule.skippedDays.filter { $0 >= today }.sorted().compactMap { key in
            parser.date(from: key).map { (key, $0) }
        }
    }

    private var daysOffSection: some View {
        Section {
            ForEach(upcomingDaysOff, id: \.key) { dayOff in
                HStack {
                    Text(dayOff.date.formatted(date: .complete, time: .omitted))
                    Spacer()
                    Button {
                        updateSchedule { $0.setSkipped(false, on: dayOff.date) }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(dayOff.date.formatted(date: .complete, time: .omitted))")
                }
            }
            HStack {
                DatePicker("Add a day off", selection: $newDayOff,
                           in: Calendar.current.startOfDay(for: Date())...,
                           displayedComponents: .date)
                Button("Add") {
                    updateSchedule {
                        $0.pruneSkippedDays(before: Date())
                        $0.setSkipped(true, on: newDayOff)
                    }
                }
                .disabled(schedule.isSkipped(newDayOff))
            }
            Button("Find Days Off in Calendar…") { showingCalendarDaysOff = true }
            Text("Work hours don't run on days off, such as holidays or vacation. Skip Today in the menu adds today. Find Days Off in Calendar suggests days your calendar shows you're out; nothing is added until you choose.")
                .font(.caption)
                .foregroundColor(.secondary)
        } header: {
            Text("Days Off")
        }
        .sheet(isPresented: $showingCalendarDaysOff) {
            CalendarDaysOffSheet(schedule: schedule) { dates in
                updateSchedule { schedule in
                    schedule.pruneSkippedDays(before: Date())
                    for date in dates { schedule.setSkipped(true, on: date) }
                }
            }
        }
    }

    // MARK: - Helpers

    /// Shows minutes from midnight in an hour-and-minute picker
    private func minutesBinding(get: @escaping () -> Int, set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: {
                let minutes = get()
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                set(min(max((parts.hour ?? 0) * 60 + (parts.minute ?? 0), 0), 1439))
            })
    }
    
    // MARK: - Custom Bindings for Nested ObservableObjects
    
    private var workScheduleEnabledBinding: Binding<Bool> {
        Binding(
            get: { appState.workScheduleManager.schedule.isEnabled },
            set: { appState.workScheduleManager.schedule.isEnabled = $0 }
        )
    }
    
    private var startTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: appState.workScheduleManager.schedule.startTimeMinutes / 60,
                    minute: appState.workScheduleManager.schedule.startTimeMinutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                if let hour = components.hour, let minute = components.minute {
                    let newStartMinutes = hour * 60 + minute
                    appState.workScheduleManager.schedule.startTimeMinutes = newStartMinutes
                    
                    // Ensure end time is always after start time (minimum 1 minute gap)
                    let minimumGap = 1
                    if appState.workScheduleManager.schedule.endTimeMinutes <= newStartMinutes + minimumGap {
                        // Cap at 23:59 (1439 minutes)
                        appState.workScheduleManager.schedule.endTimeMinutes = min(newStartMinutes + minimumGap, 1439)
                    }
                }
            }
        )
    }
    
    private var endTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: appState.workScheduleManager.schedule.endTimeMinutes / 60,
                    minute: appState.workScheduleManager.schedule.endTimeMinutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                if let hour = components.hour, let minute = components.minute {
                    let newEndMinutes = hour * 60 + minute
                    appState.workScheduleManager.schedule.endTimeMinutes = newEndMinutes
                    
                    // Ensure start time is always before end time (minimum 1 minute gap)
                    let minimumGap = 1
                    if appState.workScheduleManager.schedule.startTimeMinutes >= newEndMinutes - minimumGap {
                        // Can't go below 0
                        appState.workScheduleManager.schedule.startTimeMinutes = max(newEndMinutes - minimumGap, 0)
                    }
                }
            }
        )
    }
}

// MARK: - Day Toggle Button

struct DayToggleButton: View {
    let day: DayOfWeek
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(day.shortName)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .frame(width: 32, height: 28)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SmartFeaturesSettingsPane()
        .environmentObject(AppState())
        .frame(width: 450, height: 600)
}
