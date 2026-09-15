#!/bin/bash
# Builds dist/Phantom.app. Needs only the Xcode Command Line Tools (no full Xcode).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Phantom.app"
CONFIG="${CONFIG:-release}"

cd "$ROOT"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Phantom" "$APP/Contents/MacOS/Phantom"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/helper/phantom_helper.py" "$ROOT/scripts/bootstrap.sh" "$APP/Contents/Resources/"

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [ ! -x "$HOME/Library/Application Support/Phantom/venv/bin/python" ]; then
    echo "Device components aren't installed yet; the app offers to install them on first launch."
fi
