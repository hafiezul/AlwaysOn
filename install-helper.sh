#!/bin/bash

# AlwaysOn Installation Helper
# Re-signs a verified local app bundle to enable accessibility features

set -euo pipefail

APP_PATH="/Applications/AlwaysOn.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
EXPECTED_BUNDLE_IDENTIFIER="com.alwayson.app"
EXPECTED_VERSION="__ALWAYSON_EXPECTED_VERSION__"

fail() {
    echo "❌ Error: $1" >&2
    exit 1
}

echo "🔧 AlwaysOn Installation Helper"
echo "================================"
echo ""
echo "This script will re-sign a verified AlwaysOn.app bundle in /Applications."
echo "Only run the helper that shipped with the same release as your app download."
echo ""

command -v codesign >/dev/null 2>&1 || fail "codesign is not available on this Mac."
[ -x "$PLIST_BUDDY" ] || fail "PlistBuddy is not available on this Mac."

[ -d "$APP_PATH" ] || fail "AlwaysOn.app not found in /Applications."
[ ! -L "$APP_PATH" ] || fail "Refusing to operate on a symlinked app bundle."
[ -f "$INFO_PLIST" ] || fail "AlwaysOn.app is missing Contents/Info.plist."

BUNDLE_IDENTIFIER=$($PLIST_BUDDY -c "Print :CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null || true)
APP_VERSION=$($PLIST_BUDDY -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || true)
EXECUTABLE_NAME=$($PLIST_BUDDY -c "Print :CFBundleExecutable" "$INFO_PLIST" 2>/dev/null || true)

[ "$BUNDLE_IDENTIFIER" = "$EXPECTED_BUNDLE_IDENTIFIER" ] || fail "Unexpected bundle identifier: ${BUNDLE_IDENTIFIER:-unknown}."
[ -n "$APP_VERSION" ] || fail "Unable to read CFBundleShortVersionString from the app bundle."
[ -n "$EXECUTABLE_NAME" ] || fail "Unable to read CFBundleExecutable from the app bundle."
[ -f "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" ] || fail "App executable is missing from the bundle."

if [ "$EXPECTED_VERSION" != "__ALWAYSON_EXPECTED_VERSION__" ]; then
    EXPECTED_VERSION=${EXPECTED_VERSION#v}
    [ "$APP_VERSION" = "$EXPECTED_VERSION" ] || fail "App version $APP_VERSION does not match helper version $EXPECTED_VERSION. Download the helper from the same release page as the app."
fi

echo "✅ Verified AlwaysOn.app"
echo "   Bundle ID: $BUNDLE_IDENTIFIER"
echo "   Version:   $APP_VERSION"
echo ""
echo "🔐 Re-signing the verified app bundle (requires sudo)..."

sudo codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo ""
echo "✅ Success! AlwaysOn has been re-signed."
echo ""
echo "📋 Next steps:"
echo "1. Launch AlwaysOn from Applications"
echo "2. Go to System Settings -> Privacy & Security -> Accessibility"
echo "3. Enable AlwaysOn in the list"
echo ""
echo "Note: If you replace the app with a newer release, download that release's helper and run it again."
