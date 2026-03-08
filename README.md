<p align="center">
  <img src="AlwaysOn/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="AlwaysOn icon">
</p>

# AlwaysOn

A lightweight macOS menu bar app that keeps your status active in Microsoft Teams, Slack, Zoom, and other workplace apps by simulating minimal user activity.

If you find this app useful, consider supporting its development:

<a href="https://buymeacoffee.com/hafiezul" target="_blank"><img src="https://img.shields.io/badge/Buy%20Me%20A%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black" alt="Buy Me A Coffee"></a>

## Features

| Core | Advanced |
|------|----------|
| **Menu Bar Only** - No dock icon, lives in menu bar | **Work Hours** - Auto-enable/disable on schedule |
| **One-Click Toggle** - Start/stop instantly | **Focus Mode** - Respects Do Not Disturb |
| **Session Timer** - Track time "online" | **Presentation Detection** - Auto-pause during screen sharing |
| **Pause/Resume** - Pause without losing progress | **Quick Timers** - Auto-disable after 30min-8h |
| **Stop Session** - Reset completely | **Configurable Interval** - 30s to 5min timing |
| **Launch at Login** - Auto-start on boot | **Activity Methods** - Mouse, keyboard, or alternating |
| **Updates** - Sparkle on signed builds, manual on unsigned builds | **Schedule Notifications** - Alerts for work hours |
| **Settings Window** - Sidebar navigation | - |

## Roadmap

<details>
<summary><b>Completed</b> - Click to expand</summary>

**v1.2** - Configurable interval, quick timers, activity methods, pause/resume, stop session
**v1.3** - Work hours scheduling, presentation detection, focus mode integration, notifications
**v1.3.1** - Enhanced installation helper
</details>

<details>
<summary><b>Future Ideas</b> - Click to expand</summary>

- Homebrew Cask support (convenience only; not a code-signing workaround), menu bar icon variations, session statistics, calendar integration
- Break reminders, multiple profiles, randomized intervals, URL scheme automation
- Shortcuts.app support, WiFi location awareness, native widgets, app-specific awareness, iCloud sync
</details>

**Funding Goal** - Apple Developer Program ($99/year) to properly sign the app  
*Have an idea? [Open an issue](../../issues/new) or [start a discussion](../../discussions)!*

## Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permission (for input simulation)

## Installation

### Download Pre-built Binary (Recommended)

1. Download the latest release from the [Releases page](../../releases/latest):
   - **AlwaysOn-vX.X.X.dmg** - Drag and drop installer
   - **AlwaysOn-vX.X.X.zip** - Extract and move to Applications
2. Move `AlwaysOn.app` to your Applications folder
3. Launch `AlwaysOn.app`
4. If macOS still refuses Accessibility access for that release, **download the version-matched installation helper** from the same release page as your app:
   - Download `install-helper.sh`
   - Run it:
   ```bash
   chmod +x install-helper.sh
   ./install-helper.sh
   ```
   - After the script completes: remove the old AlwaysOn entry from **System Settings > Privacy & Security > Accessibility**, then relaunch the app
5. See [Granting Accessibility Permission](#granting-accessibility-permission) below for next steps

### From Source

Building from source is the easiest way to get full accessibility features without extra steps:

1. Clone this repository
2. Open `AlwaysOn.xcodeproj` in Xcode 15+
3. Build and run (Cmd+R)
4. See [Granting Accessibility Permission](#granting-accessibility-permission) below for next steps

```bash
git clone https://github.com/hafiezul/AlwaysOn.git
cd AlwaysOn
open AlwaysOn.xcodeproj
# Press Cmd+R in Xcode
```

**Build Requirements:** Xcode 15.0+, macOS 13.0+ SDK, Swift 5.9+

**Why build from source?** Apps built in Xcode are automatically signed with your local development certificate, so accessibility features work immediately without any manual re-signing.

### Granting Accessibility Permission

**First time setup:**
1. Click **"Keep Online"** or **"Grant Permission"** in the menu
2. macOS will show a permission prompt - click **"Open System Settings"**
3. In the Accessibility settings, enable **AlwaysOn**
4. Return to the app - it will automatically detect the permission

**Manual setup:**
1. Open **System Settings** > **Privacy & Security** > **Accessibility**
2. Click the **"+"** button and add AlwaysOn from your Applications folder
3. Ensure the checkbox next to AlwaysOn is enabled
4. Return to AlwaysOn - it will automatically detect the permission change

## Usage

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘K` | Toggle Keep Online / Pause / Resume |
| `⌘,` | Open Settings |
| `⌘Q` | Quit AlwaysOn |

## How It Works

AlwaysOn simulates minimal user activity at a configurable interval (default: 45 seconds):

**Mouse Method (Default):**
1. Moves the cursor by 1 pixel
2. Immediately moves it back
3. Repeat

**Keyboard Method:**
1. Presses and releases the Shift key
2. Repeat

**Alternating Method:**
1. Alternates between mouse and keyboard methods
2. Provides variety in activity simulation

This prevents macOS from detecting you as "idle" and keeps workplace apps like Microsoft Teams, Slack, and Zoom showing your status as "Available" or "Active".

## Updating the App

AlwaysOn supports two update modes:

- **Signed releases**: Sparkle in-app updates are enabled.
- **Unsigned releases**: Sparkle is disabled on purpose, and updates must be installed manually from GitHub Releases.

**To update manually:**

1. Visit the [Releases page](../../releases/latest)
2. Download the latest DMG or ZIP
3. Replace your existing app in the Applications folder
4. Re-run the version-matched [installation helper script](#download-pre-built-binary-recommended) only if Accessibility access breaks after the upgrade

The release notes will explicitly tell you whether a build is signed or unsigned.

## Privacy & Security

- **No network access** except for optional update checks on signed builds
- **No data collection** - Nothing is tracked or sent
- **Open source** - Audit the code yourself
- **Minimal permissions** - Only Accessibility (required for input simulation)

## FAQ

### Why does it need Accessibility permission?

macOS requires Accessibility permission for any app that simulates keyboard or mouse input. This is a security feature to prevent malicious apps from controlling your computer.

### Will this affect my actual mouse usage?

No. The movement is 1 pixel and instantly reversed.

### Does it work with Slack/Zoom/other apps?

Yes. AlwaysOn works with any app that monitors macOS system idle time, including Microsoft Teams, Slack, Zoom, Discord, and most workplace communication apps.

### Does it prevent my Mac from sleeping?

No. AlwaysOn only simulates activity, it doesn't prevent sleep.

### Why isn't it in the App Store?

Apps that simulate input can't use App Sandbox, which is required for the Mac App Store.

### How do I make it start automatically?

Enable **"Launch at Login"** in the menu. This uses macOS's built-in Login Items feature.

## Troubleshooting

### "Apple could not verify" warning after moving to Applications

macOS Gatekeeper quarantines the app when copied from a download location. Run:

```bash
xattr -r -d com.apple.quarantine /Applications/AlwaysOn.app
```

Then launch the app normally.

### App not keeping me online

1. Check that Accessibility permission is granted (see [Granting Accessibility Permission](#granting-accessibility-permission))
2. Ensure the status shows "Active" (green dot)
3. Verify your app isn't overriding with "Do Not Disturb" or custom status settings

### App doesn't appear in menu bar

1. Check if your menu bar is full (icons may be hidden)
2. Try relaunching the app
3. Check Activity Monitor for "AlwaysOn" process

### Accessibility not working after installation (DMG/ZIP)

If you installed from a pre-built DMG or ZIP and accessibility features aren't working, see the [installation helper instructions](#download-pre-built-binary-recommended) in step 4 of the installation section, then grant accessibility permission in System Settings.

### "Accessibility Required" warning won't go away

This typically happens after reinstalling or updating the app. macOS tracks permissions by app binary, so a new version appears as a different app.

**Why this happens:**
- macOS stores accessibility permissions per app binary
- When you reinstall, the old permission entry points to the old (deleted) binary
- The new app binary needs its own permission entry

**Solution:**
1. **Re-run the installation helper** (for DMG/ZIP installs) - see [installation instructions](#download-pre-built-binary-recommended)
2. Click **"Grant Permission"** in the app menu - this triggers the system prompt
3. If that doesn't work, click **"Open Settings..."** to go to Accessibility settings
4. **Remove the old entry**: Select "AlwaysOn" and click the **"-"** button
5. **Add the new app**: Click **"+"** and select AlwaysOn from your Applications folder
6. Ensure the checkbox is enabled
7. Return to the app - permission will be detected automatically

> **Tip**: The app automatically checks for permission changes when you switch back to it, and polls for 30 seconds after you open Settings.

### "Launch at Login" not working

1. Open **System Settings** > **General** > **Login Items**
2. Ensure AlwaysOn is listed and enabled
3. If not, toggle the option off and on again in the app menu

### Update check failed

1. Check your internet connection
2. Try again in a few moments
3. If the build is unsigned, use the manual check in Settings or download updates directly from the [Releases page](../../releases/latest)
4. If the build is signed, Sparkle update checks should work normally

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Submit a pull request
