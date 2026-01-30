import SwiftUI

/// About settings pane showing app information, version, and links
struct AboutSettingsPane: View {
    @Environment(\.openURL) private var openURL
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
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
                    openURL(URL(string: "https://github.com/hafiezul/AlwaysOn")!)
                } label: {
                    Label("GitHub", systemImage: "link")
                }
                .buttonStyle(.link)
                
                Button {
                    openURL(URL(string: "https://github.com/hafiezul/AlwaysOn/issues")!)
                } label: {
                    Label("Report Issue", systemImage: "exclamationmark.bubble")
                }
                .buttonStyle(.link)
                
                Button {
                    openURL(URL(string: "https://github.com/hafiezul/AlwaysOn/releases")!)
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
        .frame(width: 450, height: 350)
}
