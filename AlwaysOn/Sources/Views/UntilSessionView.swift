import SwiftUI
import AppKit

/// Start a session that runs until a chosen time, typed in or copied from a calendar event
struct UntilSessionView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var calendar = CalendarEventProvider()

    /// Called when the window should close: after a session starts, or on Cancel
    let onClose: () -> Void

    private enum Mode: String, CaseIterable, Identifiable {
        case time = "Time"
        case calendar = "Calendar Event"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .time
    @State private var endDate = UntilSessionView.roundedUpToMinute(Date().addingTimeInterval(60 * 60))
    @State private var earliestSelectable = Date()
    @State private var label = ""
    @State private var selectedEventID: String?
    @State private var errorMessage: String?

    private static let presets: [(title: String, spoken: String, minutes: Int)] = [
        ("+15m", "15 minutes", 15), ("+30m", "30 minutes", 30), ("+1h", "1 hour", 60),
        ("+2h", "2 hours", 120), ("+4h", "4 hours", 240)
    ]

    private var selectedEvent: CalendarEventSnapshot? {
        calendar.events.first { $0.id == selectedEventID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Keep Online Until")
                    .font(.title2.weight(.bold))
                Text("Starts now and stops at the time you choose, even if you pause in between.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Source", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: mode) { _ in errorMessage = nil }

            switch mode {
            case .time:
                timeSection
            case .calendar:
                UntilCalendarSection(
                    calendar: calendar,
                    selectedEventID: $selectedEventID,
                    onReload: { errorMessage = nil }
                )
            }

            Spacer(minLength: 0)

            if let errorMessage {
                errorBanner(errorMessage)
            }

            footer
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 500)
    }

    // MARK: - Time mode

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            endPreview

            VStack(alignment: .leading, spacing: 6) {
                Text("Quick picks")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    ForEach(Self.presets, id: \.minutes) { preset in
                        TimeChip(title: preset.title, accessibilityText: "Stop in \(preset.spoken)") {
                            setEnd(Date().addingTimeInterval(TimeInterval(preset.minutes * 60)))
                        }
                    }
                }
                if let workEnd = workHoursEnd {
                    TimeChip(title: "End of work hours · \(workEnd.formatted(date: .omitted, time: .shortened))",
                             accessibilityText: "Stop at the end of work hours") {
                        setEnd(workEnd)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Or pick a time")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                DatePicker("Stop at", selection: $endDate, in: earliestSelectable...,
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .onChange(of: endDate) { _ in errorMessage = nil }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Label")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                TextField("Optional, e.g. Standup or Deploy", text: $label)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    /// The chosen end time, large, with how far away it is
    private var endPreview: some View {
        HStack(spacing: 14) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 26, weight: .regular))
                .foregroundColor(.accentColor)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(endDate.formatted(date: .omitted, time: .shortened))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text(Self.relativeDescription(endDate, now: Date()))
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .accessibilityElement(children: .combine)
    }

    /// Today's work hours end, when work hours are under way and it is still ahead
    private var workHoursEnd: Date? {
        let schedule = appState.workScheduleManager.schedule
        let now = Date()
        guard schedule.isWithinSchedule(on: now),
              let end = Calendar.current.date(bySettingHour: schedule.endTimeMinutes / 60,
                                              minute: schedule.endTimeMinutes % 60, second: 0, of: now),
              end > now else { return nil }
        return end
    }

    private func setEnd(_ date: Date) {
        earliestSelectable = Self.roundedDownToMinute(Date())
        endDate = Self.roundedUpToMinute(date)
        errorMessage = nil
    }

    // MARK: - Footer

    private var primaryTitle: String {
        switch mode {
        case .time:
            return "Keep Online Until \(endDate.formatted(date: .omitted, time: .shortened))"
        case .calendar:
            guard let event = selectedEvent else { return "Choose an Event" }
            return "Keep Online Until \(event.title) Ends"
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                onClose()
            }
            .buttonStyle(ActionButtonStyle())
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button(primaryTitle) {
                start()
            }
            .buttonStyle(ActionButtonStyle(kind: .prominent))
            .lineLimit(1)
            .keyboardShortcut(.defaultAction)
            .disabled(mode == .calendar && selectedEventID == nil)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !appState.hasAccessibilityPermission {
                Button("Grant Accessibility Permission") {
                    appState.requestPermission()
                }
                .buttonStyle(ActionButtonStyle(kind: .prominent, compact: true))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private func start() {
        errorMessage = nil

        switch mode {
        case .time:
            // Validate against the current clock: the picker's lower bound was set when the window opened
            guard endDate > Date() else {
                errorMessage = "That time has already passed. Choose a time in the future."
                return
            }
            submit(endDate: endDate, label: label)

        case .calendar:
            guard let event = selectedEvent else {
                errorMessage = "Choose an event first."
                return
            }
            // The list may be old; check this exact event again at the moment of starting
            guard event.endDate > Date() else {
                errorMessage = "\u{201C}\(event.title)\u{201D} has already ended. Reload events and choose another."
                return
            }
            submit(endDate: event.endDate, label: event.title)
        }
    }

    private func submit(endDate: Date, label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let started = appState.startUntil(date: endDate, label: trimmed.isEmpty ? nil : trimmed)

        if started {
            onClose()
        } else if !appState.hasAccessibilityPermission {
            errorMessage = "AlwaysOn needs Accessibility permission to keep you online. Grant it, then start again."
        } else {
            errorMessage = "The session could not start. The end time may have just passed; choose a later time and try again."
        }
    }

    // MARK: - Helpers

    /// "Today · in 1h 5m", "Tomorrow · in 14h", or "Friday, Nov 13 · in 3 days"
    static func relativeDescription(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = "Today"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            day = "Tomorrow"
        } else {
            day = date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "\(day) · already passed" }
        let days = Int(seconds / 86_400)
        let span = days >= 2 ? "\(days) days" : ActivityDurationFormat.long(seconds)
        return "\(day) · in \(span)"
    }

    private static func roundedUpToMinute(_ date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / 60).rounded(.up) * 60)
    }

    private static func roundedDownToMinute(_ date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / 60).rounded(.down) * 60)
    }
}

// MARK: - Calendar section

/// Calendar tab: nothing is requested or read until the user presses "Load Calendar Events"
private struct UntilCalendarSection: View {
    @ObservedObject var calendar: CalendarEventProvider
    @Binding var selectedEventID: String?
    let onReload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick a meeting in the next 24 hours and stay online until it ends. AlwaysOn only reads events; it never changes your calendar.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            content

            Text("The end time is copied when you start, so moving the event later doesn't change the session.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch calendar.accessState {
        case .restricted:
            infoBlock(
                symbol: "lock.fill",
                title: "Calendar access is restricted",
                message: "A device policy (such as Screen Time or a managed profile) blocks calendar access, so it can't be turned on from here. You can still use the Time tab."
            )
            retryButton

        case .denied:
            infoBlock(
                symbol: "calendar.badge.exclamationmark",
                title: "Calendar access is off",
                message: "Open System Settings › Privacy & Security › Calendars, turn on AlwaysOn, then choose Retry. You can still use the Time tab."
            )
            HStack {
                Button("Open Calendar Privacy Settings") { Self.openCalendarPrivacySettings() }
                retryButton
            }

        case .writeOnly:
            infoBlock(
                symbol: "calendar.badge.exclamationmark",
                title: "Full calendar access needed",
                message: "AlwaysOn has add-only access, which can't read events. In System Settings › Privacy & Security › Calendars, change AlwaysOn to Full Access, then choose Retry."
            )
            HStack {
                Button("Open Calendar Privacy Settings") { Self.openCalendarPrivacySettings() }
                retryButton
            }

        case .notDetermined, .granted:
            loadableContent
        }
    }

    @ViewBuilder
    private var loadableContent: some View {
        switch calendar.phase {
        case .idle:
            Button("Load Calendar Events") { load() }
                .buttonStyle(ActionButtonStyle(kind: .prominent, compact: true))
            if calendar.accessState == .notDetermined {
                Text("macOS will ask for calendar access when you press this button.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading events…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

        case .failed(let message):
            infoBlock(symbol: "exclamationmark.triangle.fill", title: "Couldn't load events", message: message)
            retryButton

        case .loaded:
            if calendar.events.isEmpty {
                infoBlock(
                    symbol: "calendar",
                    title: "No events found",
                    message: "No current or upcoming timed events in the next 24 hours. All-day and canceled events are not shown."
                )
                Button("Reload Events") { load() }
            } else {
                eventList
                Button("Reload Events") { load() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    private var eventList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(calendar.events) { event in
                    eventCard(event)
                }
            }
            .padding(1)
        }
        .frame(minHeight: 160, maxHeight: 260)
    }

    private func eventCard(_ event: CalendarEventSnapshot) -> some View {
        let isSelected = event.id == selectedEventID
        let inProgress = event.startDate <= Date()
        return Button {
            selectedEventID = event.id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(event.title)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        if inProgress {
                            Text("Now")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.green.opacity(0.18)))
                                .foregroundColor(.green)
                        }
                    }
                    Text(timeRange(for: event) + (event.calendarTitle.map { " · \($0)" } ?? ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func timeRange(for event: CalendarEventSnapshot) -> String {
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    private var retryButton: some View {
        Button("Retry") { load() }
    }

    private func infoBlock(symbol: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundColor(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func load() {
        selectedEventID = nil
        onReload()
        Task { await calendar.loadEvents() }
    }

    private static func openCalendarPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }
}
