#!/bin/bash
# Shared by the post-merge and post-checkout hooks: rebuild and reinstall Phantom when the
# incoming changes touch app sources. Takes one argument, a revision range like "A..B".
#
# Deliberately quiet and conservative: it does nothing unless Phantom is already installed,
# and nothing unless files that actually go into the app changed.
set -euo pipefail

RANGE="${1:-}"
[ -n "$RANGE" ] || exit 0

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"  # the path filter below is relative to the repo root

INSTALLED=""
for candidate in "/Applications/Phantom.app" "$HOME/Applications/Phantom.app"; do
    if [ -d "$candidate" ]; then
        INSTALLED="$candidate"
        break
    fi
done
[ -n "$INSTALLED" ] || exit 0  # never installed, so there's nothing to keep current

CHANGED="$(git diff --name-only "$RANGE" -- Sources helper Resources Package.swift scripts/build.sh 2>/dev/null || true)"
[ -n "$CHANGED" ] || exit 0

echo "phantom: app sources changed, reinstalling $INSTALLED"
if pgrep -x Phantom >/dev/null; then
    echo "phantom: Phantom is open and will be quit (the real location is restored as it exits)"
fi
if "$ROOT/scripts/install.sh" >/dev/null 2>&1; then
    echo "phantom: updated $INSTALLED"
else
    echo "phantom: reinstall failed; run scripts/install.sh to see the error" >&2
fi
