#!/bin/bash
# Installs Phantom's device layer (pymobiledevice3) into a private virtualenv.
# Run by the app on first launch; safe to re-run to repair or upgrade.
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/Phantom"
VENV="$APP_SUPPORT/venv"
PACKAGE="pymobiledevice3>=11.12,<12"

mkdir -p "$APP_SUPPORT"

# Apps launched from Finder get a minimal PATH, so also look where uv/Homebrew usually live.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

if command -v uv >/dev/null 2>&1; then
    echo "==> Using uv at $(command -v uv)"
    uv venv --allow-existing --python 3.13 "$VENV"
    uv pip install --python "$VENV/bin/python" --upgrade "$PACKAGE"
else
    PYTHON=""
    for candidate in python3.13 python3.12 python3.11 python3.14 python3; do
        if command -v "$candidate" >/dev/null 2>&1 &&
            "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
            PYTHON="$(command -v "$candidate")"
            break
        fi
    done
    if [ -z "$PYTHON" ]; then
        echo "error: Python 3.10 or newer is required. Install uv (https://docs.astral.sh/uv/) or run 'brew install python@3.13', then try again." >&2
        exit 1
    fi
    echo "==> Using $PYTHON"
    "$PYTHON" -m venv "$VENV"
    "$VENV/bin/python" -m pip install --upgrade pip
    "$VENV/bin/python" -m pip install --upgrade "$PACKAGE"
fi

"$VENV/bin/python" -c 'import importlib.metadata as m; print("==> pymobiledevice3", m.version("pymobiledevice3"), "is ready")'
