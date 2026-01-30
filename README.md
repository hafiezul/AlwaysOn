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

### From Source

1. Clone this repository
2. Open `AlwaysOn/AlwaysOn.xcodeproj` in Xcode 15+
3. Build and run (Cmd+R)
4. When prompted, grant Accessibility permission in System Settings

### Granting Accessibility Permission

1. Open **System Settings** > **Privacy & Security** > **Accessibility**
2. Click the lock icon and authenticate
3. Enable **AlwaysOn** in the list
4. If AlwaysOn isn't listed, click "+" and add it manually

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

1. Open System Settings > Privacy & Security > Accessibility
2. Remove AlwaysOn from the list
3. Re-add it and ensure it's enabled
4. Restart AlwaysOn

## Building from Source

```bash
# Clone the repository
git clone <repository-url>
cd always-on

# Open in Xcode
open AlwaysOn/AlwaysOn.xcodeproj

# Build and run
# Press Cmd+R in Xcode
```

### Build Requirements

- Xcode 15.0+
- macOS 13.0+ SDK
- Swift 5.9+

## License

MIT License - See LICENSE file for details.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## Acknowledgments

Inspired by the need to appear "available" while focusing on deep work.
