# AlwaysOn

A lightweight macOS menu bar app that keeps your status active in Microsoft Teams, Slack, Zoom, and other workplace apps by simulating minimal user activity.

If you find this app useful, consider supporting its development:

<a href="https://buymeacoffee.com/hafiezul" target="_blank"><img src="https://img.shields.io/badge/Buy%20Me%20A%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black" alt="Buy Me A Coffee"></a>

## Features

- **Menu Bar Only** - Lives in your menu bar, no dock icon
- **One-Click Toggle** - Enable/disable with a single click
- **Pause/Resume** - Pause your session and resume later without losing progress
- **Stop Session** - Completely reset and start a fresh session
- **Minimal Resource Usage** - <15MB memory, <0.1% CPU
- **Remembers State** - Restores your preference on relaunch
- **Session Timer** - Shows how long you've been "online"
- **Launch at Login** - Automatically start when you log in
- **Auto-Updates** - Sparkle-powered automatic updates
- **Configurable Interval** - Choose activity timing (30s to 5min)
- **Settings Window** - Clean sidebar navigation for all preferences
- **Quick Timers** - Set auto-disable after 30min, 1h, 2h, 4h, or 8h
- **Activity Methods** - Choose mouse, keyboard, or alternating simulation

## Roadmap

Here's what's planned for future versions. Want to help? [Contributions](#contributing) are welcome!

### v1.2 - Customization (Completed)
- [x] **Configurable activity interval** - Adjust timing (30s, 45s, 60s, 2min, 5min)
- [x] **Quick timers** - "Keep online for X hours" with auto-disable
- [x] **Activity method options** - Choose between mouse, keyboard, or alternating
- [x] **Pause/Resume functionality** - Pause sessions and resume without losing progress
- [x] **Stop Session control** - Explicit button to reset and start fresh

### v1.3 - Smart Features
- [ ] **Work hours scheduling** - Auto-enable/disable at specific times
- [ ] **Battery-aware mode** - Longer intervals when on battery power
- [ ] **Presentation mode detection** - Auto-pause during screen sharing
- [ ] **Focus mode integration** - Respect macOS Do Not Disturb

### v1.4 - Distribution & UX
- [ ] **Homebrew Cask support** - `brew install --cask alwayson`
- [ ] **Improved auto-updates** - Download and install from within the app
- [ ] **Menu bar icon variations** - Different status indicators
- [ ] **Session statistics** - Track total uptime per day/week

### Future Ideas
- **Calendar integration** - Auto-pause during meetings
- **Break reminders** - Pomodoro-style notifications
- **Multiple profiles** - Different settings for different scenarios

### Funding Goal
- **Apple Developer Program** ($99/year) - Sign the app properly so users don't need the install-helper script!

> Have an idea? [Open an issue](../../issues/new) or [start a discussion](../../discussions)!

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
4. **Run the installation helper script** (required for accessibility features):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/hafiezul/AlwaysOn/main/install-helper.sh | bash
   ```
   Or download `install-helper.sh` from the repository and run:
   ```bash
   chmod +x install-helper.sh
   ./install-helper.sh
   ```
5. See [Granting Accessibility Permission](#granting-accessibility-permission) below for next steps

> **⚠️ Why the extra step?** macOS requires apps using accessibility features to be signed with an Apple Developer certificate ($99/year - that's a lot of coffee ☕). Since I can't afford that right now, the helper script re-signs the app locally on your machine. Takes 30 seconds and it's completely safe - this project is open source, so feel free to [inspect the script](install-helper.sh) before running it. If you'd rather skip it, just [build from source](#from-source) in Xcode!

### From Source

Building from source is the easiest way to get full accessibility features without extra steps:

1. Clone this repository
2. Open `AlwaysOn.xcodeproj` in Xcode 15+
3. Build and run (Cmd+R)
4. See [Granting Accessibility Permission](#granting-accessibility-permission) below for next steps

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

### Menu Bar Interface

**When Active:**
```
+-------------------------------+
| ● Active              v1.2.1  |  <- Green = keeping you online
+-------------------------------+
| ⏸ Pause                  ⌘K |  <- Pause your session
| ⏱ Session: 2:34:12           |  <- Live timer
+-------------------------------+
| ⚙ Settings...            ⌘, |
| ⏻ Quit AlwaysOn          ⌘Q |
+-------------------------------+
```

**When Paused (with saved session):**
```
+-------------------------------+
| ○ Inactive            v1.2.1  |
+-------------------------------+
| ▶ Resume                 ⌘K |  <- Resume saved session
| ⏱ Session: 2:34:12 (paused)  |  <- Saved progress
| ⏹ Stop Session               |  <- Reset completely
+-------------------------------+
| ⚙ Settings...            ⌘, |
| ⏻ Quit AlwaysOn          ⌘Q |
+-------------------------------+
```

**When Inactive (fresh start):**
```
+-------------------------------+
| ○ Inactive            v1.2.1  |
+-------------------------------+
| ▶ Keep Online            ⌘K |  <- Start new session
+-------------------------------+
| ⚙ Settings...            ⌘, |
| ⏻ Quit AlwaysOn          ⌘Q |
+-------------------------------+
```

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘K` | Toggle Keep Online / Pause / Resume |
| `⌘,` | Open Settings |
| `⌘Q` | Quit AlwaysOn |

### Session Controls

**Pause** - Temporarily stop activity simulation while preserving your session timer. Use this for short breaks (lunch, meetings, etc.). Click "Resume" to continue from where you left off.

**Stop Session** - Completely reset your session and clear all timers. Use this when you're done for the day or want to start tracking fresh. Next activation will be a brand new session.

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

**Why these methods?**
- Workplace apps monitor system idle time
- Tiny mouse movements and key presses reset the idle timer
- Activity is imperceptible to users
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

Yes. AlwaysOn works with any app that monitors macOS system idle time, including Microsoft Teams, Slack, Zoom, Discord, and most workplace communication apps. However, some apps may have their own activity detection methods (like webcam monitoring) that this won't bypass.

### Does it prevent my Mac from sleeping?

No. AlwaysOn only simulates activity, it doesn't prevent sleep. If you want to prevent sleep, use a separate tool like `caffeinate`.

### Why isn't it in the App Store?

Apps that simulate input can't use App Sandbox, which is required for the Mac App Store.

### How do I make it start automatically?

Enable **"Launch at Login"** in the menu. This uses macOS's built-in Login Items feature.

## Troubleshooting

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

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## Acknowledgments

Inspired by the need to appear "available" while focusing on deep work.
