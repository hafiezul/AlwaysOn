import SwiftUI

/// Settings pane for schedule automation
struct SmartFeaturesSettingsPane: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Form {
            // Work Schedule Section
            Section {
                Toggle("Enable Work Hours Schedule", isOn: workScheduleEnabledBinding)
                    .onChange(of: appState.workScheduleManager.schedule.isEnabled) { newValue in
                        if newValue {
                            appState.workScheduleManager.startMonitoring()
                        } else {
                            appState.workScheduleManager.stopMonitoring()
                        }
                    }
                
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
                    
                    // Status
                    HStack {
                        Image(systemName: appState.workScheduleManager.isWithinSchedule ? "clock.fill" : "clock")
                            .foregroundColor(appState.workScheduleManager.isWithinSchedule ? .green : .secondary)
                        Text(appState.workScheduleManager.statusDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Notifications toggle
                    Toggle("Show Notifications", isOn: notificationsEnabledBinding)
                        .font(.subheadline)
                    
                    // Show permission status if denied
                    if appState.notificationManager.authorizationStatus == .denied {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Notifications not allowed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Open Settings") {
                                appState.notificationManager.openNotificationSettings()
                            }
                            .font(.caption)
                        }
                    }
                }
                
                Text("Automatically enable AlwaysOn during your work hours and disable outside of them.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Label("Work Hours Schedule", systemImage: "calendar.badge.clock")
            }
            
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Custom Bindings for Nested ObservableObjects
    
    private var workScheduleEnabledBinding: Binding<Bool> {
        Binding(
            get: { appState.workScheduleManager.schedule.isEnabled },
            set: { appState.workScheduleManager.schedule.isEnabled = $0 }
        )
    }
    
    private var notificationsEnabledBinding: Binding<Bool> {
        Binding(
            get: { appState.notificationManager.isEnabled },
            set: { appState.notificationManager.isEnabled = $0 }
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
