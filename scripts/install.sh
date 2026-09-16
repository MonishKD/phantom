#!/bin/bash
# Builds Phantom and installs it into Applications, so it shows up in Spotlight and Launchpad.
# Pass --dock to also pin it to the Dock (this restarts the Dock).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build.sh"

# /Applications is writable by admin users; fall back to the per-user folder otherwise.
DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"
APP="$DEST/Phantom.app"

if pgrep -x Phantom >/dev/null; then
    echo "==> Quitting the running copy (the helper restores the real location as it exits)"
    pkill -x Phantom || true
    for _ in $(seq 1 20); do
        pgrep -x Phantom >/dev/null || break
        sleep 0.5
    done
fi

rm -rf "$APP"
# Move, not copy: a leftover dist/Phantom.app shows up as a second Phantom in Spotlight and Launchpad.
mv "$ROOT/dist/Phantom.app" "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -u "$ROOT/dist/Phantom.app" >/dev/null 2>&1 || true
touch "$APP"  # nudge Spotlight and Launchpad to re-index

echo "==> Installed $APP"

if [ "${1:-}" = "--dock" ]; then
    defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$APP</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
    killall Dock
    echo "==> Pinned to the Dock"
fi

echo "Open it with Spotlight (⌘-Space, type Phantom), from Launchpad, or: open -a Phantom"
