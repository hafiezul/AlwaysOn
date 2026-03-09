<p align="center">
  <img src="AlwaysOn/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="AlwaysOn icon">
</p>

# AlwaysOn

A lightweight macOS menu bar app that keeps your status active in Microsoft Teams, Slack, Zoom, and other workplace apps by simulating minimal user activity.

If you find this app useful, consider supporting its development:

<a href="https://buymeacoffee.com/hafiezul" target="_blank"><img src="https://img.shields.io/badge/Buy%20Me%20A%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black" alt="Buy Me A Coffee"></a>

## What it does

- Lives in the menu bar with no Dock icon.
- Starts, pauses, resumes, or stops activity simulation in one click.
- Supports mouse, keyboard, or alternating activity methods.
- Includes quick timers, work hours, launch at login, and named profiles.
- Shows where a session came from, such as a manual start, quick timer, or work schedule.

## Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permission (for input simulation)

## Installation

### Pre-built app

1. Download the latest release from the [Releases page](../../releases/latest):
   - `AlwaysOn-vX.X.X.dmg` for drag-and-drop install
   - `AlwaysOn-vX.X.X.zip` for manual extraction
2. Move `AlwaysOn.app` to `/Applications`
3. Launch `AlwaysOn.app`
4. If Accessibility still fails for that release, download the matching `install-helper.sh` from the same release and run:

```bash
chmod +x install-helper.sh
./install-helper.sh
```

5. Remove the old AlwaysOn entry from **System Settings > Privacy & Security > Accessibility**, then relaunch the app

### From Source

Building from source is the simplest way to avoid extra signing steps.

1. Clone this repository
2. Open `AlwaysOn.xcodeproj` in Xcode 15+
3. Build and run (Cmd+R)
4. Grant Accessibility permission when prompted

```bash
git clone https://github.com/hafiezul/AlwaysOn.git
cd AlwaysOn
open AlwaysOn.xcodeproj
```

Build requirements: Xcode 15+, macOS 13+ SDK, Swift 5.9+

## First-run setup

1. Click **"Keep Online"** or **"Grant Permission"** in the menu
2. Click **"Open System Settings"** when macOS prompts you
3. In the Accessibility settings, enable **AlwaysOn**
4. Return to the app and it will detect the permission automatically

## Usage

- Use the menu bar icon to start, pause, resume, or stop a session.
- Pick an activity method and interval in Settings.
- Use quick timers for short sessions or Work Hours for scheduled automation.
- Create profiles for different setups such as work, meetings, or focus time.
- If automation stops a session, AlwaysOn shows a notification so the change is visible.

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘K` | Toggle Keep Online / Pause / Resume |
| `⌘,` | Open Settings |
| `⌘Q` | Quit AlwaysOn |

## How It Works

AlwaysOn simulates minimal user activity at a configurable interval (default: 45 seconds):

- Mouse: move the cursor by 1 pixel, then move it back.
- Keyboard: press and release the Shift key.
- Alternating: switch between mouse and keyboard methods.

This keeps macOS from marking you idle, which helps workplace apps keep your status as active.

## Updates

- Signed releases support Sparkle in-app updates.
- Unsigned releases must be updated manually from [GitHub Releases](../../releases/latest).
- If Accessibility breaks after an upgrade, re-run the version-matched `install-helper.sh`.

Release notes state whether a build is signed or unsigned.

## Privacy & Security

- No data collection
- No network access except optional update checks on signed builds
- Only Accessibility permission is required
- Fully open source

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

## Troubleshooting

### macOS says the app could not be verified

Run:

```bash
xattr -r -d com.apple.quarantine /Applications/AlwaysOn.app
```

Then launch the app again.

### Accessibility still is not working

1. Re-run the version-matched `install-helper.sh` if you installed from a DMG or ZIP
2. Open **System Settings > Privacy & Security > Accessibility**
3. Remove the old AlwaysOn entry if one exists
4. Add `AlwaysOn.app` again and enable it
5. Relaunch the app

### The app is not keeping me online

1. Confirm Accessibility permission is enabled
2. Confirm AlwaysOn shows an active session
3. Check whether your chat app is forcing a custom presence state

### The app does not appear in the menu bar

1. Check whether the menu bar is crowded and the icon is hidden
2. Relaunch the app
3. Check Activity Monitor for `AlwaysOn`

### Launch at Login is not working

1. Open **System Settings** > **General** > **Login Items**
2. Ensure AlwaysOn is listed and enabled
3. If not, toggle the option off and on again in the app menu

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome. Open an issue, start a discussion, or submit a pull request.
