#!/bin/bash
# Regenerates the README screenshots in screenshots/, in light and dark.
#
#   Scripts/screenshots/render.sh
#
# Needs a Mac with Xcode. It compiles AlwaysOn's real views together with
# Shots.swift into a separate renderer app, then draws each view offscreen into
# a PNG with cacheDisplay. Nothing appears on screen and nothing is captured
# from it, so it needs no Screen Recording permission.
#
# The renderer works on a patched copy of the sources in a temporary folder:
# it never posts input, registers the global hotkey, or holds power
# assertions, and it keeps its settings and activity history apart from an
# installed AlwaysOn. The repository's sources are not modified.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$REPO/Scripts/screenshots"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SRC="$WORK/src"
mkdir -p "$SRC"
cp -R "$REPO/AlwaysOn/Sources/." "$SRC/"
cp "$REPO/CLI/Sources/alwayson/CLIInstallation.swift" "$SRC/"
rm "$SRC/App/AlwaysOnApp.swift" "$SRC/Services/AppUpdater.swift"
cp "$HERE/AppUpdaterStub.swift" "$SRC/"

# apply_patch FILE PERL_EXPRESSION CHECK: applies a patch and fails if CHECK is then missing
apply_patch() {
  perl -0pi -e "$2" "$SRC/$1"
  grep -qF -- "$3" "$SRC/$1" || { echo "Patch no longer applies to $1; update render.sh" >&2; exit 1; }
}

# Never post input, register the hotkey, or hold power assertions
apply_patch Services/ActivitySimulator.swift \
  's/(func start\(schedule: PulseSchedule, method: ActivityMethod = \.mouse\) \{)/$1\n        isRunning = true; return/' \
  'isRunning = true; return'
apply_patch Services/GlobalHotKeyManager.swift \
  's/(func register\(keyCode: UInt32, modifiers: UInt32\) -> Bool \{)/$1\n        return true \/\/ shots/' \
  'return true // shots'
apply_patch Services/PowerAssertionManager.swift \
  's/(func hold\(_ newLevel: PowerAssertionLevel\?\) \{)/$1\n        return \/\/ shots/' \
  'return // shots'
# Report Accessibility as granted so the menu shows its normal state
apply_patch Services/AccessibilityPermission.swift \
  's/(private func checkPermission\(\) -> Bool \{)/$1\n        return true \/\/ shots/' \
  'return true // shots'
# Read history from the renderer's sample file, never the real one
apply_patch Services/ActivityHistoryStore.swift \
  's/static var defaultFileURL: URL\? \{.*?\n    \}/static var defaultFileURL: URL? {\n        URL(fileURLWithPath: ProcessInfo.processInfo.environment["ALWAYSON_SHOTS_HISTORY"]!)\n    }/s' \
  'ALWAYSON_SHOTS_HISTORY'
# Let the renderer backdate the running timer
apply_patch Models/AppState.swift \
  's/private\(set\) var timerStartedAt/var timerStartedAt/' \
  '    var timerStartedAt'

APP="$WORK/AlwaysOnShots.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.alwayson.app.screenshots</string>
  <key>CFBundleExecutable</key><string>AlwaysOnShots</string>
  <key>CFBundleName</key><string>AlwaysOn</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

echo "Building the renderer..."
find "$SRC" -name '*.swift' -print0 > "$WORK/sources"
xargs -0 xcrun --sdk macosx swiftc -swift-version 5 -parse-as-library -Onone \
  -target "$(uname -m)-apple-macos13.0" \
  -suppress-warnings \
  -o "$APP/Contents/MacOS/AlwaysOnShots" \
  "$HERE/Shots.swift" < "$WORK/sources"
codesign --force --sign - "$APP" 2>/dev/null

export ALWAYSON_SHOTS_OUT="$REPO/screenshots"
export ALWAYSON_SHOTS_HISTORY="$WORK/activity-history.json"
# en_US keeps dates and times consistent with the English README
"$APP/Contents/MacOS/AlwaysOnShots" -AppleLocale en_US -AppleLanguages '(en)'
"$APP/Contents/MacOS/AlwaysOnShots" --dark -AppleLocale en_US -AppleLanguages '(en)'
