import SwiftUI

/// The setup window: every permission AlwaysOn uses, what each one is for,
/// where it stands, and the next step. Only Accessibility is required.
struct PermissionsView: View {
    @ObservedObject var appState: AppState
    /// First run shows Quit and requires Accessibility before continuing
    let isFirstRun: Bool
    var onContinue: () -> Void
    var onQuit: () -> Void

    @State private var calendarAccess = CalendarEventProvider.currentAccessState()
    @State private var calendarProvider = CalendarEventProvider()
    @State private var showsTroubleshooting = false

    private var rows: [PermissionRowModel] {
        PermissionRowModel.all(appState: appState, calendarAccess: calendarAccess) {
            Task { @MainActor in calendarAccess = await calendarProvider.requestAccessOnly() }
        }
    }

    private var hasAccessibility: Bool { appState.hasAccessibilityPermission }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            section("Required") {
                PermissionRow(model: rows[0], showsRequiredBadge: false)
                if !hasAccessibility { troubleshooting }
            }

            section("Optional") {
                ForEach(Array(rows.dropFirst().enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider() }
                    PermissionRow(model: row)
                }
            }

            section("Privacy") {
                UsageStatisticsToggle(telemetry: appState.telemetry, source: .setup)
            }

            footer
        }
        .padding(24)
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user may be back from System Settings with a new answer
            refreshStatuses()
        }
        .onAppear {
            refreshStatuses()
            // The statistics switch here counts as the first time AlwaysOn asks
            if isFirstRun { appState.menuAsks.noteSetupOffered(now: Date()) }
        }
        .animation(.easeInOut(duration: 0.2), value: hasAccessibility)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(isFirstRun ? "Set Up AlwaysOn" : "Permissions")
                    .font(.title2.weight(.bold))
                Text(hasAccessibility
                     ? "You're ready. Optional permissions turn on extra features, and you can change them any time."
                     : "AlwaysOn needs Accessibility to keep you active. The others turn on optional features.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
        }
    }

    private var troubleshooting: some View {
        DisclosureGroup(isExpanded: $showsTroubleshooting) {
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Open Privacy & Security > Accessibility.")
                Text("2. If AlwaysOn is listed but doesn't work, select it and click the minus button. This can happen once after upgrading from an older release, or after building AlwaysOn yourself.")
                Text("3. Click Allow… above, or add /Applications/AlwaysOn.app with the plus button and switch it on.")
                Button("Open Accessibility Settings") { appState.openAccessibilitySettings() }
                    .buttonStyle(.link)
                    .padding(.top, 2)
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
        } label: {
            Text("Switched on but still not working?")
                .font(.caption.weight(.medium))
        }
        .padding(.leading, 42)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if isFirstRun {
                Button("Quit AlwaysOn", action: onQuit)
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            if isFirstRun && !hasAccessibility {
                Text("Allow Accessibility to continue")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Button(isFirstRun ? "Continue" : "Done", action: onContinue)
                .buttonStyle(ActionButtonStyle(kind: .prominent))
                .keyboardShortcut(.defaultAction)
                .disabled(isFirstRun && !hasAccessibility)
        }
    }

    private func refreshStatuses() {
        appState.accessibilityPermission.refresh()
        calendarAccess = CalendarEventProvider.currentAccessState()
        Task { await appState.notificationManager.checkAuthorizationStatus() }
    }
}
