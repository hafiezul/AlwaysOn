import SwiftUI

/// About settings pane showing app information, version, and links
struct AboutSettingsPane: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var appState: AppState
    @State private var copiedDiagnostics = false
    
    private var appVersion: String {
        Bundle.main.appVersion
    }
    
    private var buildNumber: String {
        Bundle.main.buildNumber
    }
    
    private var copyrightYear: String {
        let year = Calendar.current.component(.year, from: Date())
        return String(year)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // App icon and name
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                
                Text("AlwaysOn")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Keep your status active")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Version info
            VStack(spacing: 4) {
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .padding(.horizontal, 40)
            
            // Links
            HStack(spacing: 24) {
                Button {
                    openURL(AppUpdateRepository.repositoryURL)
                } label: {
                    Label("Star on GitHub", systemImage: "star")
                }
                .buttonStyle(.link)
                
                Button {
                    openURL(AppUpdateRepository.issuesURL.appending(path: "new").appending(queryItems: [URLQueryItem(name: "template", value: "bug_report.yml")]))
                } label: {
                    Label("Report Issue", systemImage: "exclamationmark.bubble")
                }
                .buttonStyle(.link)
                
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(appState.diagnosticReport().text, forType: .string)
                    copiedDiagnostics = true
                } label: {
                    Label(copiedDiagnostics ? "Copied" : "Copy Diagnostics",
                          systemImage: copiedDiagnostics ? "checkmark" : "doc.on.clipboard")
                }
                .buttonStyle(.link)
                .help("Copies version, settings, and recent input attempts to paste into an issue. No names, networks, apps, or calendar details.")
                
                Button {
                    openURL(AppUpdateRepository.releasesPageURL)
                } label: {
                    Label("Releases", systemImage: "tag")
                }
                .buttonStyle(.link)
            }
            
            Spacer()
            
            // Copyright
            Text("Copyright \(copyrightYear) Hafiezul")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AboutSettingsPane()
        .environmentObject(AppState())
        .frame(width: 450, height: 350)
}
