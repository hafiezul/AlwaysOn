<p align="center">
  <img src="AlwaysOn/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="AlwaysOn icon">
</p>

# AlwaysOn

AlwaysOn is a macOS menu bar app that keeps your presence active in Microsoft Teams, Slack, Zoom, and similar workplace apps by simulating minimal user activity.

If you find this app useful, consider supporting its development:

<a href="https://buymeacoffee.com/hafiezul" target="_blank"><img src="https://img.shields.io/badge/Buy%20Me%20A%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black" alt="Buy Me A Coffee"></a>

## At a Glance

- macOS 13.0 or later
- Requires Accessibility permission
- Runs in the menu bar with no Dock icon
- Built with Xcode 15+ and Swift 5.9+

## Core Features

- Start, pause, resume, or stop activity simulation from the menu bar
- Use mouse, keyboard, or alternating activity methods
- Run quick timers or automate sessions with work hours
- Enable launch at login and optional notifications
- Save profiles for different activity and schedule setups

## Getting Started

### Install a Release

1. Download the latest build from the [Releases page](../../releases/latest).
2. Open the DMG and drag `AlwaysOn.app` to Applications.
3. Launch AlwaysOn from Applications.
4. If macOS says Apple could not verify the app is free of malware, open **System Settings > Privacy & Security**, scroll to **Security**, click **Open Anyway** for AlwaysOn, then confirm **Open Anyway**.
5. Grant Accessibility permission when prompted.

If Accessibility breaks after a reinstall or update, remove the old AlwaysOn entry from **System Settings > Privacy & Security > Accessibility**, then add and enable `/Applications/AlwaysOn.app` again.

### Build From Source

1. Clone this repository.
2. Open `AlwaysOn.xcodeproj` in Xcode 15+.
3. Build and run.
4. Grant Accessibility permission when prompted.

```bash
git clone https://github.com/hafiezul/AlwaysOn.git
cd AlwaysOn
open AlwaysOn.xcodeproj
```

Build requirements: Xcode 15+, Swift 5.9+, macOS 13+ SDK.

## How It Works

AlwaysOn simulates minimal input on a configurable interval, with 45 seconds as the default.

- Mouse: moves the cursor by 1 pixel and immediately moves it back
- Keyboard: presses and releases the Shift key
- Alternating: switches between mouse and keyboard input

This keeps macOS from marking the system idle, which many workplace apps use to determine presence.

## Permissions and Updates

- Accessibility permission is required because the app simulates keyboard or mouse input.
- Releases are unsigned and updated manually from [GitHub Releases](../../releases/latest).
- If Accessibility stops working after an upgrade or reinstall, remove the old entry in Accessibility settings and add `AlwaysOn.app` again.
- The app does not collect data.

## Troubleshooting

### macOS says the app could not be verified

Try launching AlwaysOn once, then open **System Settings > Privacy & Security**, scroll to **Security**, click **Open Anyway** for AlwaysOn, and confirm **Open Anyway**. macOS should remember this choice for future launches.

### Accessibility permission is not working

Remove any old AlwaysOn entry from **System Settings > Privacy & Security > Accessibility**, add `/Applications/AlwaysOn.app` again, enable it, and relaunch AlwaysOn.

### The app is not keeping status active

Confirm Accessibility permission is enabled, confirm AlwaysOn shows an active session, and check whether your chat app is overriding presence with a custom status.

## License

MIT License. See [LICENSE](LICENSE).

## Contributing

Contributions are welcome through issues, discussions, and pull requests.
