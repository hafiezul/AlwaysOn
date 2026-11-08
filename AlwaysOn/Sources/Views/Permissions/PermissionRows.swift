import SwiftUI

/// One permission as the setup window and Settings show it
struct PermissionRowModel: Identifiable {
    enum Tone { case good, attention, neutral }

    enum Kind: String { case accessibility, notifications, location, calendar }

    let kind: Kind
    let title: String
    let purpose: String
    let symbol: String
    let isRequired: Bool
    let statusText: String
    let tone: Tone
    /// The button that moves this permission forward, nil when nothing is left to do
    let actionTitle: String?
    let action: (() -> Void)?

    var id: Kind { kind }
}

extension PermissionRowModel {
    /// Every permission AlwaysOn uses, required first
    @MainActor
    static func all(appState: AppState,
                    calendarAccess: CalendarAccessState,
                    requestCalendar: @escaping () -> Void) -> [PermissionRowModel] {
        [accessibility(appState), notifications(appState), location(appState),
         calendar(calendarAccess, request: requestCalendar)]
    }

    @MainActor
    static func accessibility(_ appState: AppState) -> PermissionRowModel {
        let granted = appState.hasAccessibilityPermission
        return PermissionRowModel(
            kind: .accessibility,
            title: "Accessibility",
            purpose: "Sends the tiny mouse or Shift key input that keeps you shown as active.",
            symbol: "hand.point.up.left.fill",
            isRequired: true,
            statusText: granted ? "Allowed" : "Not allowed",
            tone: granted ? .good : .attention,
            actionTitle: granted ? nil : "Allow…",
            action: granted ? nil : { appState.requestPermission() }
        )
    }

    @MainActor
    static func notifications(_ appState: AppState) -> PermissionRowModel {
        let manager = appState.notificationManager
        let purpose = "Tells you when work hours, a timer, a safety stop, or a Wi-Fi switch changes your session."
        switch manager.authorizationStatus {
        case .denied:
            return PermissionRowModel(kind: .notifications, title: "Notifications", purpose: purpose,
                                      symbol: "bell.badge.fill", isRequired: false,
                                      statusText: "Turned off in System Settings", tone: .attention,
                                      actionTitle: "Open Settings", action: { manager.openNotificationSettings() })
        case .authorized where manager.isEnabled, .provisional where manager.isEnabled:
            return PermissionRowModel(kind: .notifications, title: "Notifications", purpose: purpose,
                                      symbol: "bell.badge.fill", isRequired: false,
                                      statusText: "On", tone: .good, actionTitle: nil, action: nil)
        default:
            // Not asked yet, or allowed by macOS but switched off in AlwaysOn
            return PermissionRowModel(kind: .notifications, title: "Notifications", purpose: purpose,
                                      symbol: "bell.badge.fill", isRequired: false,
                                      statusText: "Off", tone: .neutral,
                                      actionTitle: "Turn On", action: { manager.isEnabled = true })
        }
    }

    @MainActor
    static func location(_ appState: AppState) -> PermissionRowModel {
        let monitor = appState.wifiMonitor
        let purpose = "Lets AlwaysOn read the Wi-Fi network name to switch profiles. Your position is never used."
        let base = (kind: Kind.location, title: "Location", symbol: "wifi")
        switch monitor.locationAccess {
        case .granted:
            return PermissionRowModel(kind: base.kind, title: base.title, purpose: purpose, symbol: base.symbol,
                                      isRequired: false, statusText: "Allowed", tone: .good,
                                      actionTitle: nil, action: nil)
        case .notDetermined:
            return PermissionRowModel(kind: base.kind, title: base.title, purpose: purpose, symbol: base.symbol,
                                      isRequired: false, statusText: "Not set up", tone: .neutral,
                                      actionTitle: "Allow…", action: { monitor.requestLocationAccess() })
        case .denied:
            return PermissionRowModel(kind: base.kind, title: base.title, purpose: purpose, symbol: base.symbol,
                                      isRequired: false, statusText: "Turned off in System Settings", tone: .attention,
                                      actionTitle: "Open Settings", action: { WiFiNetworkMonitor.openLocationSettings() })
        case .restricted:
            return PermissionRowModel(kind: base.kind, title: base.title, purpose: purpose, symbol: base.symbol,
                                      isRequired: false, statusText: "Blocked by device policy", tone: .neutral,
                                      actionTitle: nil, action: nil)
        }
    }

    static func calendar(_ access: CalendarAccessState, request: @escaping () -> Void) -> PermissionRowModel {
        let purpose = "Lets Keep Online Until end a session when a meeting ends. AlwaysOn only reads event times and titles."
        func row(_ status: String, _ tone: Tone, _ title: String?, _ action: (() -> Void)?) -> PermissionRowModel {
            PermissionRowModel(kind: .calendar, title: "Calendar", purpose: purpose, symbol: "calendar",
                               isRequired: false, statusText: status, tone: tone, actionTitle: title, action: action)
        }
        switch access {
        case .granted: return row("Allowed", .good, nil, nil)
        case .notDetermined: return row("Not set up", .neutral, "Allow…", request)
        case .denied: return row("Turned off in System Settings", .attention, "Open Settings",
                                 { CalendarEventProvider.openCalendarSettings() })
        case .writeOnly: return row("Needs Full Access", .attention, "Open Settings",
                                    { CalendarEventProvider.openCalendarSettings() })
        case .restricted: return row("Blocked by device policy", .neutral, nil, nil)
        }
    }
}

/// A permission row: what it is for, where it stands, and the next step
struct PermissionRow: View {
    let model: PermissionRowModel
    var compact = false

    private var toneColor: Color {
        switch model.tone {
        case .good: return .green
        case .attention: return .orange
        case .neutral: return .secondary
        }
    }

    private var statusSymbol: String {
        switch model.tone {
        case .good: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.circle.fill"
        case .neutral: return "circle.dashed"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: model.symbol)
                .font(.system(size: compact ? 13 : 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: compact ? 24 : 30, height: compact ? 24 : 30)
                .background(
                    RoundedRectangle(cornerRadius: compact ? 6 : 7, style: .continuous)
                        .fill(iconBackground)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.title)
                        .font(.body.weight(.medium))
                    if model.isRequired {
                        Text("Required")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundColor(.accentColor)
                    }
                }
                if !compact {
                    Text(model.purpose)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Label(model.statusText, systemImage: statusSymbol)
                    .font(.caption)
                    .foregroundColor(toneColor)
                    .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 8)

            if let title = model.actionTitle, let action = model.action {
                Button(title, action: action)
                    .buttonStyle(ActionButtonStyle(kind: model.isRequired ? .prominent : .plain, compact: true))
                    .fixedSize()
            }
        }
        .padding(.vertical, compact ? 2 : 4)
        .accessibilityElement(children: .combine)
    }

    private var iconBackground: Color {
        switch model.kind {
        case .accessibility: return .blue
        case .notifications: return .red
        case .location: return .teal
        case .calendar: return .orange
        }
    }
}
