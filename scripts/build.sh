#!/bin/bash
# Builds dist/Phantom.app. Needs only the Xcode Command Line Tools (no full Xcode).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Phantom.app"
CONFIG="${CONFIG:-release}"

cd "$ROOT"
# Record the current SDK in the binary, not just the deployment target: macOS gates newer system
# behaviour on the SDK an app was linked against, so without this Phantom is treated as a legacy app.
swift build -c "$CONFIG" -Xlinker -platform_version -Xlinker macos -Xlinker 26.0 -Xlinker 27.0
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Phantom" "$APP/Contents/MacOS/Phantom"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/helper/phantom_helper.py" "$ROOT/scripts/bootstrap.sh" "$APP/Contents/Resources/"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [ ! -x "$HOME/Library/Application Support/Phantom/venv/bin/python" ]; then
    echo "Device components aren't installed yet; the app offers to install them on first launch."
fi
