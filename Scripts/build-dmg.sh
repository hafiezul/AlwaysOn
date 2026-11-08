#!/bin/bash
# Packages a built AlwaysOn.app into the drag-to-install DMG, with the
# designed installer window (background art, icon layout, volume icon).
#
#   Scripts/build-dmg.sh <path/to/AlwaysOn.app> <output.dmg>
#
# dmgbuild writes the layout straight into the image's .DS_Store, so this works
# headless on CI runners. The art (background.png, background@2x.png) and its
# geometry (layout.json) live in Scripts/dmg/; see make-background.py.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <AlwaysOn.app> <output.dmg>" >&2
  exit 64
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG_DIR="$REPO_ROOT/Scripts/dmg"
APP_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
DMG_PATH="$2"
DMGBUILD_VERSION="1.6.7"

test -d "$APP_PATH"
mkdir -p "$(dirname "$DMG_PATH")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 -m venv "$WORK/venv"
"$WORK/venv/bin/python" -m pip install --quiet "dmgbuild==$DMGBUILD_VERSION"

rm -f "$DMG_PATH"
"$WORK/venv/bin/dmgbuild" \
  -s "$DMG_DIR/settings.py" \
  -D app="$APP_PATH" \
  -D layout="$DMG_DIR/layout.json" \
  -D background="$DMG_DIR" \
  "AlwaysOn" "$DMG_PATH"

printf 'Built DMG: %s\n' "$DMG_PATH"
