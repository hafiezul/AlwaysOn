# AlwaysOn

A lightweight macOS menu bar app that keeps your Microsoft Teams status "Available" by simulating minimal user activity.

If you find this app useful, consider supporting its development:

<a href="https://buymeacoffee.com/hafiezul" target="_blank"><img src="https://img.shields.io/badge/Buy%20Me%20A%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black" alt="Buy Me A Coffee"></a>

## Features

- **Menu Bar Only** - Lives in your menu bar, no dock icon
- **One-Click Toggle** - Enable/disable with a single click
- **Minimal Resource Usage** - <15MB memory, <0.1% CPU
- **Remembers State** - Restores your preference on relaunch
- **Session Timer** - Shows how long you've been "online"
- **Launch at Login** - Automatically start when you log in
- **Check for Updates** - Stay up to date with the latest version
- **About Window** - View version info and check for updates

## Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permission (for input simulation)

## Installation

### Download Pre-built Binary (Recommended)

1. Download the latest release from the [Releases page](../../releases/latest):
   - **AlwaysOn-vX.X.X.dmg** - Drag and drop installer
   - **AlwaysOn-vX.X.X.zip** - Extract and move to Applications
2. Move `AlwaysOn.app` to your Applications folder
3. **First launch**: Right-click the app and select "Open" (required for unsigned apps)
4. When prompted, grant Accessibility permission in System Settings

> **Note**: Since the app is not signed with an Apple Developer certificate, macOS will show a warning on first launch. This is normal for open-source apps distributed outside the App Store. After right-clicking and selecting "Open" once, subsequent launches will work normally.

### From Source

1. Clone this repository
2. Open `AlwaysOn.xcodeproj` in Xcode 15+
3. Build and run (Cmd+R)
4. When prompted, grant Accessibility permission in System Settings

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

### Menu Bar Interface

```
+-------------------------------+
| * Active              v1.1.0  |  <- Green = keeping you online
+-------------------------------+
| || Pause                   ^K |  <- Toggle on/off
| () Session: 2:34:12           |  <- Live timer (updates while open)
+-------------------------------+
| [] Launch at Login            |  <- Toggle auto-start
| <> Check for Updates          |  <- Check GitHub for updates
+-------------------------------+
| (i) About AlwaysOn            |  <- Version info & links
| (!) Quit AlwaysOn          ^Q |
+-------------------------------+

When permission is needed:
+-------------------------------+
| o Inactive                    |
+-------------------------------+
| > Keep Online              ^K |
+-------------------------------+
| /!\ Accessibility Required    |
|     Click below to grant...   |
| [=] Grant Permission          |  <- Triggers system prompt
| [o] Open Settings...          |  <- Manual fallback
+-------------------------------+
| (!) Quit AlwaysOn          ^Q |
+-------------------------------+
```

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘K` | Toggle Keep Online |
| `⌘Q` | Quit AlwaysOn |

## How It Works

AlwaysOn simulates minimal mouse activity every 45 seconds:

1. Moves the cursor by 1 pixel
2. Immediately moves it back
3. Repeat

This prevents macOS from detecting you as "idle" and keeps apps like Microsoft Teams showing your status as "Available".

**Why mouse movement?**
- Teams monitors system idle time
- Tiny mouse movements reset the idle timer
- Movement is imperceptible to users
- Uses native macOS APIs (no hacks)

## Updating the App

AlwaysOn can check for updates directly from GitHub:

1. Click **"Check for Updates"** in the menu, or
2. Open **"About AlwaysOn"** and click **"Check for Updates"**

If an update is available, click **"Download Update"** to open the GitHub releases page where you can download the latest version.

> **Tip**: After downloading a new version, you may need to remove the old entry from Accessibility settings and re-add the new app. See Troubleshooting below.

## Privacy & Security

- **No network access** - App works entirely offline (except for update checks)
- **No data collection** - Nothing is tracked or sent
- **Open source** - Audit the code yourself
- **Minimal permissions** - Only Accessibility (required for input simulation)

## FAQ

### Why does it need Accessibility permission?

macOS requires Accessibility permission for any app that simulates keyboard or mouse input. This is a security feature to prevent malicious apps from controlling your computer.

### Will this affect my actual mouse usage?

No. The movement is 1 pixel and instantly reversed. You won't notice it.

### Does it work with Slack/Zoom/other apps?

Most likely yes. Any app that uses macOS idle detection should be affected. However, some apps may have their own activity detection that this won't bypass.

### Does it prevent my Mac from sleeping?

No. AlwaysOn only simulates activity, it doesn't prevent sleep. If you want to prevent sleep, use a separate tool like `caffeinate`.

### Why isn't it in the App Store?

Apps that simulate input can't use App Sandbox, which is required for the Mac App Store.

### How do I make it start automatically?

Enable **"Launch at Login"** in the menu. This uses macOS's built-in Login Items feature.

## Troubleshooting

### App not keeping me online

1. Check that Accessibility permission is granted
2. Ensure the status shows "Active" (green dot)
3. Verify Teams isn't overriding with "Do Not Disturb"

### App doesn't appear in menu bar

1. Check if your menu bar is full (icons may be hidden)
2. Try relaunching the app
3. Check Activity Monitor for "AlwaysOn" process

### "Accessibility Required" warning won't go away

This typically happens after reinstalling or updating the app. macOS tracks permissions by app binary, so a new version appears as a different app.

**Why this happens:**
- macOS stores accessibility permissions per app binary
- When you reinstall, the old permission entry points to the old (deleted) binary
- The new app binary needs its own permission entry

**Solution:**
1. Click **"Grant Permission"** in the app menu - this triggers the system prompt
2. If that doesn't work, click **"Open Settings..."** to go to Accessibility settings
3. **Remove the old entry**: Select "AlwaysOn" and click the **"-"** button
4. **Add the new app**: Click **"+"** and select AlwaysOn from your Applications folder
5. Ensure the checkbox is enabled
6. Return to the app - permission will be detected automatically

> **Tip**: The app automatically checks for permission changes when you switch back to it, and polls for 30 seconds after you open Settings.

### "Launch at Login" not working

1. Open **System Settings** > **General** > **Login Items**
2. Ensure AlwaysOn is listed and enabled
3. If not, toggle the option off and on again in the app menu

### Update check failed

1. Check your internet connection
2. Try again in a few moments
3. You can always download updates manually from the [Releases page](../../releases/latest)

## Building from Source

```bash
# Clone the repository
git clone https://github.com/hafiezul/AlwaysOn.git
cd AlwaysOn

# Open in Xcode
open AlwaysOn.xcodeproj

# Build and run
# Press Cmd+R in Xcode
```

### Build Requirements

- Xcode 15.0+
- macOS 13.0+ SDK
- Swift 5.9+

### Creating a Release

To create a new release:

```bash
# Tag the commit with a version
git tag v1.1.0
git push origin v1.1.0
```

GitHub Actions will automatically build the app and create a release with both ZIP and DMG downloads.

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## Acknowledgments

Inspired by the need to appear "available" while focusing on deep work.
