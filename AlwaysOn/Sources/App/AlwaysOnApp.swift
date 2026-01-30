import SwiftUI

@main
struct AlwaysOnApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.isActive ? "circle.fill" : "circle")
        }
        .menuBarExtraStyle(.window)
    }
}
