#!/bin/bash

# AlwaysOn Installation Helper
# Re-signs the app locally to enable accessibility features
# Source: https://github.com/hafiezul/AlwaysOn

set -e

echo "🔧 AlwaysOn Installation Helper"
echo "================================"
echo ""
echo "This script will re-sign the AlwaysOn app to enable accessibility features."
echo "You'll need to enter your password for sudo access."
echo ""

APP_PATH="/Applications/AlwaysOn.app"

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: AlwaysOn.app not found in /Applications"
    echo "Please install AlwaysOn.app to /Applications first."
    exit 1
fi

echo "✅ Found AlwaysOn.app"
echo ""
echo "🔐 Re-signing the app (requires sudo)..."

# Re-sign the app with ad-hoc signature
# This allows it to access accessibility features on the local machine
sudo codesign --force --deep --sign - "$APP_PATH"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Success! AlwaysOn has been re-signed."
    echo ""
    echo "📋 Next steps:"
    echo "1. Launch AlwaysOn from Applications"
    echo "2. Go to System Settings → Privacy & Security → Accessibility"
    echo "3. Enable AlwaysOn in the list"
    echo ""
    echo "Note: If you update AlwaysOn, you'll need to run this script again."
else
    echo ""
    echo "❌ Error: Failed to re-sign the app."
    echo "Please check the error message above."
    exit 1
fi
