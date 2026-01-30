import SwiftUI

@main
struct AlwaysOnApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Label {
                Text("AlwaysOn")
            } icon: {
                Image(systemName: appState.isActive ? "circle.fill" : "circle")
                    .foregroundColor(appState.isActive ? .green : .gray)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
