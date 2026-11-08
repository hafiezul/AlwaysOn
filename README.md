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
- Toggle the session from anywhere with the ⌥⌘K global hotkey
- Use mouse, keyboard, or alternating activity methods
- Optionally skip simulated input while you are actively using the machine
- Optionally pause simulation while no chat or meeting app is running
- Pause automatically while the Mac sleeps, locks, or switches users
- Run quick timers or automate sessions with work hours
- Keep online until a chosen time or until a calendar event ends
- Keep online while a terminal command runs, with the `alwayson` CLI
- Review recent input attempts in the Pulse Log
- See daily online time for the last week in Settings > Activity
- Stop automatically after you've been away too long or the battery runs low
- Control sessions from Shortcuts, Spotlight, and Siri
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

### Power use

AlwaysOn only wakes the CPU when something can change:

- Simulation pauses while the Mac sleeps or another user is switched in, and resumes with an immediate input when you return. By default it also pauses while the screen is locked, since most chat apps show you as Away on a locked Mac and input posted to the lock screen keeps waking the display. Turn off **Settings > General > Pause while screen is locked** to keep simulating while locked.
- The session clock ticks every second only while the menu is open or in the last minute of a timer. Otherwise it wakes when the menu bar countdown changes, and an unlimited session with the menu closed needs no clock at all.
- Work hours wake AlwaysOn at the schedule's start and end instead of checking every minute. Deadlines and the schedule are re-checked right after wake and after clock or time zone changes.
- The target-app option tracks app launches and quits instead of scanning running apps on every tick.
- Accessibility permission is checked when it matters (opening the menu, starting a session, each tick) instead of every 10 seconds. While you grant it, AlwaysOn checks every second for up to two minutes.
- Timers carry a tolerance so macOS can batch their wake-ups.

## Launcher Commands

AlwaysOn registers the `alwayson://` URL scheme, so launchers like Raycast and Alfred can drive it:

- `alwayson://start` starts a session
- `alwayson://stop` stops the session
- `alwayson://toggle` starts or pauses
- `alwayson://timer?minutes=30` keeps online for 30 minutes. Omit `minutes` to use the profile default.

## Keep online until a set time

Choose **Until...** in the menu to start a session now that stops at a time you pick. The window has two tabs:

- **Time**: pick a date and time, or use **+30 min**, **+1 hr**, **+2 hr**, or **+4 hr**. Add an optional label.
- **Calendar**: choose **Load Calendar Events**, then pick a timed event that is in progress or starts in the next 24 hours. The session uses the event's title as its label and stops when the event ends.

AlwaysOn copies the end time when you start the session. If the event moves or gets shorter in Calendar later, the session keeps the copied end time. AlwaysOn does not detect meetings or start sessions on its own.

The menu shows the end date and time under the session and, while it runs, a countdown. The end time is absolute:

- If you pause, the session still ends at that time, and resuming continues to the same end time.
- If AlwaysOn quits while the session runs, it resumes the session on relaunch only if the end time is still in the future.
- **Cancel Timer** removes the end time and keeps the session running with no limit.

AlwaysOn refuses to start if the time has already passed or Accessibility permission is missing. In both cases the current session keeps running unchanged.

AlwaysOn asks for calendar access only when you choose **Load Calendar Events**. It reads event titles and times and never changes your calendar. If you deny access, the **Time** tab still works. To turn access on later, open **System Settings > Privacy & Security > Calendars**. On macOS 14 and later, AlwaysOn needs **Full Access**. Add-only access cannot read events.

## Check what AlwaysOn sent

Choose **Pulse Log...** in the menu to see each input attempt as it happens. Each entry shows its time and one outcome:

- **Input posted**: AlwaysOn sent the mouse or Shift input.
- **Skipped: user active**: you used the machine in the last 30 seconds and the idle-only option is on.
- **Skipped: no target app**: no chosen chat or meeting app was running and that option is on.
- **Input creation failed**: macOS did not create the input event.
- **Paused: Mac asleep, locked, or switched user**: simulation stopped until the Mac is back in use.
- **Stopped: Accessibility permission missing**: permission was revoked, so the session stopped.

The log shows the newest 200 entries and counts each outcome since launch or the last clear. **Clear Log** empties both. The log stays in memory and disappears when AlwaysOn quits. It records what AlwaysOn sent, not the status that Teams, Slack, or other apps show.

## Activity history

**Settings > Activity** shows today's online time, the last 7 days, and a daily chart split by how each session started (manual, work hours, timer, Until, or command). The menu shows today's total next to the status.

Online time counts while a session is active and the Mac is awake. Time paused for sleep, a locked screen, or a switched-out user isn't counted. History stays on this Mac in `~/Library/Application Support/AlwaysOn/activity-history.json`, keeps the last 30 days, and is written only when a session starts or stops, plus a checkpoint at most every 5 minutes. **Clear History…** removes it.

## Safety stops

Two optional limits in **Settings > General > Safety** end a session on their own. Both are off by default.

- **Stop after I'm away for** 1, 2, 4, or 8 hours: ends the session once you haven't touched the keyboard or mouse for that long. AlwaysOn tells your input apart from its own, so its simulated input doesn't reset the clock. Starting or resuming a session counts as being present.
- **Stop on low battery** at 10, 20, 30, or 50%: ends the session when the battery reaches that level while unplugged, and refuses to start below it. It follows the power source through macOS notifications instead of polling.

A safety stop appears in the menu and the Pulse Log, and sends a notification when notifications are on.

## Shortcuts

AlwaysOn adds these actions to the Shortcuts app:

- **Keep Online**, with optional minutes (1–1440)
- **Keep Online Until** a date and time, with an optional label
- **Pause or Resume**, which returns whether AlwaysOn is now active
- **Stop Session**
- **Switch Profile**, which stops the current session like switching from the menu
- **Get Status**, which returns whether AlwaysOn is active

They follow the same rules as the `alwayson://` links and report an error if Accessibility permission is missing. "Start AlwaysOn", "Stop AlwaysOn", and "AlwaysOn status" also work from Spotlight and Siri.

## Keep online while a command runs

The native `alwayson` CLI is bundled inside AlwaysOn.app. It requires the installed macOS app and Accessibility permission granted beforehand. There is no Python runtime dependency.

Open **Settings > General > Command Line Tool** and click **Install**. The section shows the installation state, command path, and bundled version/build. Click **Uninstall** there to remove this app's link. If another AlwaysOn copy owns the link, **Use This App** switches it to the current copy.

You can also install through the bundled CLI:

```bash
"/Applications/AlwaysOn.app/Contents/Helpers/alwayson" install
# Add this to your shell configuration if ~/.local/bin is not on PATH:
export PATH="$HOME/.local/bin:$PATH"
```

Installation creates a symlink in `~/.local/bin`, or in `install --directory PATH`. It refuses to replace unrelated files or symlinks. Use `alwayson uninstall [--directory PATH]` to remove only this app's managed link. The symlink follows app replacements at the same path. `alwayson --version` or `alwayson version` reads that app's marketing version and build; there are no independent CLI versions or binaries. Controls route explicitly to the owning app, even when multiple AlwaysOn apps exist. `~/.local/bin` needs to be on PATH only for interactive shell lookup.

Other requests are `alwayson start`, `stop`, `toggle`, `timer MINUTES` with integer minutes 1...1440, and `until HH:MM` or `until ISO8601`. A local HH:MM must be in the future today; it never rolls into tomorrow. Requests report transport success, without app acknowledgement.

For development, use `swift build --package-path CLI`, then `python3 CLI/Tests/acceptance.py CLI/.build/debug/alwayson`. The package has no external dependencies. The tests copy the built executable into app fixtures and replace the OS URL launcher through `ALWAYSON_URL_OPENER`. Production macOS requests use Launch Services with running-app substitution disabled. Unbundled development builds support help/version but refuse installation and control; install the full app for those operations. The macOS app does not run on Linux.

Put the command after `--`:

```bash
alwayson run -- make test
alwayson run -- python3 long_job.py
```

The helper runs the command with its arguments unchanged, without a shell. Output streams to your terminal as the command writes it, and the helper exits with the command's exit status. A command killed by a signal gives the shell-style status 128 plus the signal number.

### How the helper starts and stops sessions

Before the command starts, the helper opens `alwayson://run?token=UUID`. After the command exits, it opens `alwayson://finish?token=UUID` with the same token. Each run gets a new token. AlwaysOn ignores a `run` or `finish` URL whose token is missing, malformed, or repeated.

- A `run` request replaces the current session, and the menu shows the session's end time. If Accessibility permission is missing, AlwaysOn asks for it and keeps the current session.
- A `finish` request stops the session only if its token matches the current command session.
- The latest command wins. When overlapping commands finish, an older command cannot stop a newer session.
- Pausing, resuming, starting another session, cancelling the timer, stopping, or switching profiles ends command ownership. A later `finish` from that command does nothing.
- After you pause and resume, the session keeps the command's 24-hour safety end time.

Ctrl-C reaches the command directly. The helper waits for the command to exit, then releases the session. If the helper itself receives SIGTERM (for example, from `kill`) or SIGHUP (for example, when the terminal closes), it forwards the signal to the command and still releases the session.

### Limits

- URL delivery has no application acknowledgement. Successful delivery does not confirm permission, that the session started, or the order in which requests arrived.
- If the helper exits without sending `finish` (for example, after SIGKILL), the session stops at its 24-hour safety end time.
- Command sessions do not resume after AlwaysOn relaunches.
- AlwaysOn does not prevent system sleep.

## Permissions and Updates

- Accessibility permission is required because the app simulates keyboard or mouse input.
- Calendar access is optional. AlwaysOn asks for it only when you load events in the **Until...** window.
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
