#!/bin/bash
# Builds the Release app, embeds the version from arguments, and ad-hoc signs
# the result. Used by CI (push and PR builds) and the release workflow.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${VERSION:-0.0.0-local}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
BUILD_DIR="${BUILD_DIR:-"$REPO_ROOT/build"}"
APP_PATH="$BUILD_DIR/Build/Products/Release/AlwaysOn.app"

xcodebuild \
  -project AlwaysOn.xcodeproj \
  -scheme AlwaysOn \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -arch arm64 -arch x86_64 \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM="" \
  build

codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

printf 'Built and ad-hoc signed: %s\n' "$APP_PATH"
