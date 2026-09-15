#!/bin/bash
# Turns on the repo's hooks, which keep an installed Phantom.app in step with the code.
# Undo with: git config --unset core.hooksPath
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# core.hooksPath replaces .git/hooks wholesale, so say something if hooks already live there.
EXISTING="$(find .git/hooks -maxdepth 1 -type f ! -name '*.sample' 2>/dev/null || true)"
if [ -n "$EXISTING" ]; then
    echo "note: these hooks in .git/hooks will stop running while core.hooksPath is set:"
    echo "$EXISTING" | sed 's/^/  /'
fi

chmod +x scripts/hooks/* scripts/*.sh
git config core.hooksPath scripts/hooks

echo "Hooks enabled. After a pull or branch switch that changes app sources,"
echo "Phantom is rebuilt and reinstalled automatically (only if it's already installed)."
