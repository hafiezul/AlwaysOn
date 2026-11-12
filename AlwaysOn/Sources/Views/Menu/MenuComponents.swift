import SwiftUI

// Building blocks for the menu bar window. They follow native menu metrics:
// 12 pt side insets, 22-26 pt rows, and a soft highlight on hover.

enum MenuMetrics {
    static let width: CGFloat = 288
    static let inset: CGFloat = 12
    static let iconWidth: CGFloat = 16
}

/// A full-width menu row: icon, title, optional trailing hint
struct MenuRow: View {
    let title: String
    let systemImage: String
    var hint: String?
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            MenuRowLabel(title: title, systemImage: systemImage, hint: hint,
                         tint: role == .destructive ? .red : nil)
        }
        .buttonStyle(MenuRowButtonStyle())
    }
}

struct MenuRowLabel: View {
    let title: String
    let systemImage: String
    var hint: String?
    var tint: Color?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: MenuMetrics.iconWidth)
                .foregroundColor(tint ?? .secondary)
            Text(title)
                .foregroundColor(tint ?? .primary)
            Spacer(minLength: 8)
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, MenuMetrics.inset)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Hover and press highlight for menu rows, inset like native menu items
struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRowBody(configuration: configuration)
    }

    private struct MenuRowBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : (isHovered ? 0.09 : 0)))
                        .padding(.horizontal, 5)
                )
                .onHover { isHovered = $0 }
        }
    }
}

/// Filled action buttons drawn entirely in SwiftUI, so they look the same in
/// the menu window whether or not it is key
struct ActionButtonStyle: ButtonStyle {
    enum Kind { case prominent, plain }

    var kind: Kind = .plain
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        ActionBody(configuration: configuration, kind: kind, compact: compact)
    }

    private struct ActionBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let compact: Bool
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(compact ? .callout : .body.weight(.medium))
                .foregroundColor(kind == .prominent ? .white : .primary)
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 4 : 7)
                .background(
                    RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous)
                        .fill(fill)
                )
                .opacity(isEnabled ? 1 : 0.5)
                .onHover { isHovered = $0 }
        }

        private var fill: Color {
            let pressed = configuration.isPressed
            switch kind {
            case .prominent:
                return Color.accentColor.opacity(pressed ? 0.75 : (isHovered ? 0.9 : 1))
            case .plain:
                return Color.primary.opacity(pressed ? 0.18 : (isHovered ? 0.12 : 0.07))
            }
        }
    }
}

/// A compact pill for one-tap durations ("30m", "+1h")
struct TimeChip: View {
    let title: String
    let accessibilityText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(ChipButtonStyle())
        .accessibilityLabel(accessibilityText)
    }
}

private struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration)
    }

    private struct ChipBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.18 : (isHovered ? 0.12 : 0.06)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
                .onHover { isHovered = $0 }
        }
    }
}

/// One line of context under the status card: why a session ended, what the
/// schedule does next, or what needs attention
struct NoticeRow: View {
    let text: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
                .foregroundColor(tint)
                .frame(width: MenuMetrics.iconWidth)
            Text(text)
                .foregroundColor(tint == .secondary ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pulse Log presentation

extension PulseLog.Outcome {
    var symbol: String {
        switch self {
        case .posted: return "checkmark.circle"
        case .userActive: return "hand.raised"
        case .noTarget: return "app.dashed"
        case .inputCreationFailed: return "xmark.octagon"
        case .inputNotRegistered: return "exclamationmark.triangle"
        case .systemPaused: return "moon.zzz"
        case .permissionMissing: return "lock.slash"
        case .stoppedAway: return "figure.walk"
        case .stoppedLowBattery: return "battery.25"
        }
    }

    var tint: Color {
        switch self {
        case .posted: return .green
        case .userActive, .stoppedAway, .stoppedLowBattery: return .orange
        case .noTarget: return .secondary
        case .systemPaused: return .indigo
        case .inputCreationFailed, .inputNotRegistered, .permissionMissing: return .red
        }
    }

    /// One word for list rows: Posted, Skipped, Paused, Failed, Stopped
    var shortTitle: String {
        switch self {
        case .posted: return "Posted"
        case .userActive, .noTarget: return "Skipped"
        case .systemPaused: return "Paused"
        case .inputCreationFailed, .inputNotRegistered: return "Failed"
        case .permissionMissing, .stoppedAway, .stoppedLowBattery: return "Stopped"
        }
    }
}

/// The latest input attempts as a row of ticks, newest on the right. Clicking
/// opens the full Pulse Log.
struct PulseStrip: View {
    @ObservedObject var pulseLog: PulseLog
    let onOpen: () -> Void

    private static let tickCount = 24

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .frame(width: MenuMetrics.iconWidth)
                    .foregroundColor(.secondary)
                if let latest = pulseLog.history.last {
                    ticks
                    Spacer(minLength: 4)
                    Text(latest.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                } else {
                    Text("Pulse Log…")
                    Spacer()
                }
            }
            .padding(.horizontal, MenuMetrics.inset)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
        .help("Open the Pulse Log")
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Opens the Pulse Log")
    }

    private var ticks: some View {
        let recent = pulseLog.history.suffix(Self.tickCount)
        return HStack(spacing: 2) {
            ForEach(0..<(Self.tickCount - recent.count), id: \.self) { _ in
                Capsule().fill(Color.primary.opacity(0.08)).frame(width: 3, height: 12)
            }
            ForEach(Array(recent)) { entry in
                Capsule()
                    .fill(entry.outcome.tint.opacity(entry.outcome == .posted ? 0.85 : 0.6))
                    .frame(width: 3, height: entry.outcome == .posted ? 12 : 7)
                    .frame(height: 12, alignment: .bottom)
            }
        }
    }

    private var accessibilitySummary: String {
        guard let latest = pulseLog.history.last else { return "Pulse Log" }
        return "Pulse Log. Latest: \(latest.summary) at \(latest.date.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - Window visibility

/// Reports whether the menu's window is on screen. MenuBarExtra windows are
/// reused and ordered out rather than closed, so this follows the window's
/// occlusion state instead of relying on onAppear alone.
struct MenuVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: VisibilityView, context: Context) {
        view.onChange = onChange
    }

    final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        private var token: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            guard let window else { report(false); return }
            token = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                           object: window, queue: .main) { [weak self, weak window] _ in
                self?.report(window?.occlusionState.contains(.visible) ?? false)
            }
            report(window.occlusionState.contains(.visible))
        }

        /// Deferred so state changes never happen inside a SwiftUI view update
        private func report(_ visible: Bool) {
            DispatchQueue.main.async { [weak self] in self?.onChange?(visible) }
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}
