import SwiftUI

/// First-launch permissions window view
/// Presents a clear, friendly UI to guide users through granting accessibility permission
struct PermissionsView: View {
    @ObservedObject var accessibilityPermission: AccessibilityPermission
    var onContinue: () -> Void
    var onQuit: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with app icon and title
            headerSection
            
            // Privacy notice
            privacyNotice
            
            // Permission card
            permissionCard
            
            // Footer with Quit/Continue buttons
            footerSection
        }
        .padding(24)
        .frame(width: 460)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            // App Icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
            
            // Title
            Text("Permissions")
                .font(.largeTitle)
                .fontWeight(.bold)
        }
        .padding(.bottom, 16)
    }
    
    // MARK: - Privacy Notice
    
    private var privacyNotice: some View {
        VStack(spacing: 8) {
            Text("AlwaysOn needs permission to keep your status active.")
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            
            Text("No personal information is collected or stored.")
                .font(.callout)
                .foregroundColor(.green)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .padding(.bottom, 16)
    }
    
    // MARK: - Permission Card
    
    private var permissionCard: some View {
        VStack(spacing: 16) {
            // Title with underline
            Text(accessibilityPermission.title)
                .font(.title2)
                .fontWeight(.semibold)
                .underline()
            
            // Explanation
            VStack(alignment: .leading, spacing: 8) {
                Text("AlwaysOn needs this to:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(accessibilityPermission.details, id: \.self) { detail in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .fontWeight(.bold)
                            Text(detail)
                        }
                    }
                }
                .font(.body)
            }
            
            // Grant Permission button
            Button(action: {
                accessibilityPermission.request()
            }) {
                HStack(spacing: 8) {
                    if accessibilityPermission.hasPermission {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Permission Granted")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "lock.open")
                        Text("Grant Permission")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .disabled(accessibilityPermission.hasPermission)
            .animation(.easeInOut(duration: 0.2), value: accessibilityPermission.hasPermission)
            
            // Troubleshooting tip
            if !accessibilityPermission.hasPermission {
                troubleshootingTip
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
        )
        .padding(.bottom, 16)
    }
    
    // MARK: - Troubleshooting Tip
    
    private var troubleshootingTip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Tip")
                    .fontWeight(.medium)
            }
            .font(.caption)
            
            Text("If you reinstalled the app, you may need to remove the old entry from System Settings > Privacy & Security > Accessibility first.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Button(action: {
                accessibilityPermission.openSettings()
            }) {
                Text("Open Settings...")
                    .font(.caption)
            }
            .buttonStyle(.link)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.yellow.opacity(0.1))
        )
    }
    
    // MARK: - Footer Section
    
    private var footerSection: some View {
        HStack(spacing: 12) {
            Button(action: onQuit) {
                Text("Quit")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            
            Button(action: onContinue) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!accessibilityPermission.hasPermission)
            .keyboardShortcut(.defaultAction)
        }
    }
}

#Preview {
    PermissionsView(
        accessibilityPermission: AccessibilityPermission(),
        onContinue: {},
        onQuit: {}
    )
}
