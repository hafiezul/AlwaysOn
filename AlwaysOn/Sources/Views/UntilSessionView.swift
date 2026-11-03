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
        case calendar = "Calendar"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .time
    @State private var endDate = UntilSessionView.roundedUpToMinute(Date().addingTimeInterval(60 * 60))
    @State private var earliestSelectable = Date()
    @State private var label = ""
    @State private var selectedEventID: String?
    @State private var errorMessage: String?

    private static let presets: [(title: String, minutes: Int)] = [
        ("+30 min", 30), ("+1 hr", 60), ("+2 hr", 120), ("+4 hr", 240)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        .frame(minWidth: 440, minHeight: 480)
    }

    // MARK: - Time mode

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start keeping you online now and stop at the time you choose.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DatePicker(
                "Stop at",
                selection: $endDate,
                in: earliestSelectable...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .onChange(of: endDate) { _ in errorMessage = nil }

            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.minutes) { preset in
                    Button(preset.title) {
                        let now = Date()
                        earliestSelectable = Self.roundedDownToMinute(now)
                        endDate = Self.roundedUpToMinute(now.addingTimeInterval(TimeInterval(preset.minutes * 60)))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            TextField("Label (optional)", text: $label)
                .textFieldStyle(.roundedBorder)

            Label(
                "Ends \(endDate.formatted(date: .abbreviated, time: .shortened))",
                systemImage: "clock"
            )
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") {
                onClose()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button(mode == .time ? "Start Until Chosen Time" : "Start Until Event Ends") {
                start()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(mode == .calendar && selectedEventID == nil)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !appState.hasAccessibilityPermission {
                Button("Grant Accessibility Permission") {
                    appState.requestPermission()
                }
                .controlSize(.small)
            }
        }
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
            guard let event = calendar.events.first(where: { $0.id == selectedEventID }) else {
                errorMessage = "Choose an event first."
                return
            }
            // The list may be old; check this exact event again at the moment of starting
            guard event.endDate > Date() else {
                errorMessage = "“\(event.title)” has already ended. Reload events and choose another."
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
            Text("Pick a current or upcoming event (next 24 hours) and keep online until it ends. AlwaysOn only reads events; it never changes your calendar.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            content

            Text("The end time is copied when you start. If the event is moved or shortened later, the session keeps the original end time. AlwaysOn does not detect meetings or start automatically.")
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
                if let event = calendar.events.first(where: { $0.id == selectedEventID }) {
                    Label(
                        "Will stop at \(event.endDate.formatted(date: .abbreviated, time: .shortened))",
                        systemImage: "clock"
                    )
                    .font(.subheadline)
                }
                Button("Reload Events") { load() }
                    .controlSize(.small)
            }
        }
    }

    private var eventList: some View {
        List(calendar.events, selection: $selectedEventID) { event in
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.body)
                    .lineLimit(1)
                Text("\(startDescription(for: event)) · ends \(event.endDate.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let calendarTitle = event.calendarTitle, !calendarTitle.isEmpty {
                    Text(calendarTitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(minHeight: 150)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
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

    private func startDescription(for event: CalendarEventSnapshot) -> String {
        if event.startDate <= Date() {
            return "In progress"
        }
        return "Starts \(event.startDate.formatted(date: .omitted, time: .shortened))"
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
