# AlwaysOn

A lightweight macOS menu bar app that keeps your Microsoft Teams status "Available" by simulating minimal user activity.

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/hafiezul)

## Features

- **Menu Bar Only** - Lives in your menu bar, no dock icon
- **One-Click Toggle** - Enable/disable with a single click
- **Minimal Resource Usage** - <15MB memory, <0.1% CPU
- **Remembers State** - Restores your preference on relaunch
- **Session Timer** - Shows how long you've been "online"

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

1. Open **System Settings** > **Privacy & Security** > **Accessibility**
2. Click the lock icon and authenticate
3. Enable **AlwaysOn** in the list
4. If AlwaysOn isn't listed, click "+" and add it manually
5. Return to AlwaysOn - it will automatically detect the permission change

> **Note**: If the app still shows "Accessibility Required" after granting permission, click "Re-check Permission" in the menu or simply click away and reopen the menu.

## Usage

### Menu Bar Interface

```
┌─────────────────────────┐
│ ● Active            ▸   │  ← Green = keeping you online
├─────────────────────────┤
│ ⏸ Pause           ⌘K   │  ← Toggle on/off
│ ─────────────────────── │
│ 🕐 Session: 2:34:12     │  ← Time since activated
│ ─────────────────────── │
│ ⏻ Quit AlwaysOn    ⌘Q   │
└─────────────────────────┘
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

## Privacy & Security

- **No network access** - App works entirely offline
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

This can happen after reinstalling or updating the app, as macOS tracks permissions by app binary.

**Quick fix:**
1. Click "Open Settings" in the app menu
2. In System Settings, toggle AlwaysOn **off** then **on** again
3. Click "Re-check Permission" in the app menu

**If that doesn't work:**
1. Open System Settings > Privacy & Security > Accessibility
2. Remove AlwaysOn from the list (select it and click "-")
3. Click "+" and re-add AlwaysOn from your Applications folder
4. Ensure it's enabled (checkbox is checked)
5. Click "Re-check Permission" in the app menu

> **Tip**: The app automatically detects permission changes when you switch back to it, or you can manually click "Re-check Permission" at any time.

## Building from Source

```bash
# Clone the repository
git clone <repository-url>
cd always-on

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
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions will automatically build the app and create a release with both ZIP and DMG downloads.

## License

MIT License - See LICENSE file for details.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## Acknowledgments

Inspired by the need to appear "available" while focusing on deep work.
