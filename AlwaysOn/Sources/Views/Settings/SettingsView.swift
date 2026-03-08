import SwiftUI

/// Main Settings view with NavigationSplitView sidebar
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedItem: SettingsNavigationItem = .general

    init(initialSelection: SettingsNavigationItem = .general) {
        _selectedItem = State(initialValue: initialSelection)
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(SettingsNavigationItem.allCases, selection: $selectedItem) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 220)
        } detail: {
            // Detail pane
            detailView
                .frame(minWidth: 400, minHeight: 300)
        }
        .navigationTitle("Settings")
        .frame(minWidth: 580, minHeight: 350)
    }
    
    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .general:
            GeneralSettingsPane()
                .environmentObject(appState)
        case .smartFeatures:
            SmartFeaturesSettingsPane()
                .environmentObject(appState)
        case .updates:
            UpdatesSettingsPane()
        case .profiles:
            ProfilesSettingsPane()
                .environmentObject(appState)
        case .about:
            AboutSettingsPane()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
