#!/bin/bash
# Builds the Release app, embeds the version from arguments, and signs the
# result inside out. Used by CI (push and PR builds) and the release workflow.
#
#   SIGN_IDENTITY   codesign identity (SHA-1 or name). Defaults to "-" (ad-hoc).
#                   Releases sign with the long-lived self-signed certificate so
#                   macOS keeps Accessibility access across updates; see
#                   CODESIGNING.md.
#   SIGN_KEYCHAIN   optional keychain that holds SIGN_IDENTITY
#   SPARKLE_PUBLIC_ED_KEY
#                   EdDSA public key for Sparkle. Without it the app has no
#                   auto-updater (local and CI builds).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${VERSION:-0.0.0-local}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
BUILD_DIR="${BUILD_DIR:-"$REPO_ROOT/build"}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
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
  SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM="" \
  build

sign() {
  local args=(--force --sign "$SIGN_IDENTITY")
  if [[ -n "$SIGN_KEYCHAIN" ]]; then
    args+=(--keychain "$SIGN_KEYCHAIN")
  fi
  codesign "${args[@]}" "$@"
}

# Nested code first, the app bundle last. Hardened runtime stays off: its library
# validation needs an Apple Team ID, which a self-signed certificate lacks.
CLI_PATH="$APP_PATH/Contents/Helpers/alwayson"
test -x "$CLI_PATH"
sign "$CLI_PATH"

SPARKLE="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [[ ! -d "$SPARKLE" ]]; then
  echo "Sparkle.framework was not embedded in $APP_PATH" >&2
  exit 1
fi
SPARKLE_B="$SPARKLE/Versions/B"
for xpc in "$SPARKLE_B"/XPCServices/*.xpc; do
  [[ -e "$xpc" ]] || continue
  sign --preserve-metadata=entitlements "$xpc"
done
sign "$SPARKLE_B/Autoupdate"
sign "$SPARKLE_B/Updater.app"
sign "$SPARKLE"

sign --entitlements "$REPO_ROOT/AlwaysOn/AlwaysOn.entitlements" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

REQUIREMENT="$(codesign --display --requirements - "$APP_PATH" 2>&1 | sed -n 's/^#* *designated => //p')"
printf 'Designated requirement: %s\n' "$REQUIREMENT"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  printf 'Built and ad-hoc signed: %s\n' "$APP_PATH"
else
  # TCC keys Accessibility access to this requirement. A cdhash requirement
  # changes with every build, which is what resets permissions after an update.
  if [[ "$REQUIREMENT" != *certificate* ]]; then
    echo "Expected a certificate-based designated requirement, got: $REQUIREMENT" >&2
    exit 1
  fi
  printf 'Built and signed with %s: %s\n' "$SIGN_IDENTITY" "$APP_PATH"
fi
