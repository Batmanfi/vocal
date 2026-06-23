#!/usr/bin/env bash
set -euo pipefail

# Installs Vocal into /Applications so it is launchable from Spotlight and Launchpad.
# The signing identity is unchanged, so the Accessibility / Input Monitoring / Microphone
# grants you already gave carry over to the installed copy (same designated requirement).

APP_NAME="Vocal"
BUNDLE_ID="local.vocal.app"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_APP="$ROOT_DIR/dist/$APP_NAME.app"
DEST_APP="/Applications/$APP_NAME.app"

cd "$ROOT_DIR"

# The Python ASR venv lives next to the project, not inside /Applications. Pin its
# absolute path in config.json so the installed app always finds parakeet-mlx
# regardless of where the bundle is located.
VENV_PYTHON="$ROOT_DIR/.venv/bin/python"
if [ -x "$VENV_PYTHON" ]; then
  echo "Pinning Python interpreter in config.json: $VENV_PYTHON"
  CONFIG_PATH="$HOME/.config/vocal/config.json" VENV_PYTHON="$VENV_PYTHON" /usr/bin/python3 - <<'PY'
import json, os
path = os.environ["CONFIG_PATH"]
os.makedirs(os.path.dirname(path), exist_ok=True)
cfg = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            cfg = json.load(f)
    except Exception:
        cfg = {}
cfg["python_executable"] = os.environ["VENV_PYTHON"]
with open(path, "w") as f:
    json.dump(cfg, f, indent=2, sort_keys=True)
PY
else
  echo "WARNING: $VENV_PYTHON not found. Create it with:"
  echo "  python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
fi

echo "Building and staging the app bundle..."
./script/build_and_run.sh stage

echo "Stopping any running instances..."
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -f "$DEST_APP/Contents/Resources/parakeet_daemon.py" >/dev/null 2>&1 || true
pkill -f "$SRC_APP/Contents/Resources/parakeet_daemon.py" >/dev/null 2>&1 || true
sleep 1

echo "Copying to $DEST_APP ..."
rm -rf "$DEST_APP"
/usr/bin/ditto "$SRC_APP" "$DEST_APP"

# Re-sign the installed copy with the same identity (ditto preserves it, but re-signing
# guarantees the designated requirement is intact at the new location).
SIGNING_IDENTITY_NAME="Vocal Self-Signed"
SIGNING_HASH="$(security find-identity -p codesigning 2>/dev/null \
  | grep "$SIGNING_IDENTITY_NAME" | head -1 | awk '{print $2}')"
if [ -n "$SIGNING_HASH" ]; then
  /usr/bin/codesign --force --identifier "$BUNDLE_ID" --sign "$SIGNING_HASH" "$DEST_APP" >/dev/null
else
  /usr/bin/codesign --force --identifier "$BUNDLE_ID" --sign - "$DEST_APP" >/dev/null
fi

echo "Launching $DEST_APP ..."
/usr/bin/open "$DEST_APP"
sleep 2
pgrep -x "$APP_NAME" >/dev/null && echo "Vocal is running from /Applications." || echo "Vocal did not start."

echo
echo "Done. You can now open Vocal from Spotlight (⌘Space → 'Vocal') or Launchpad."
echo "If recording or paste stops working, re-grant Accessibility + Input Monitoring to the"
echo "/Applications copy once (Settings deep-link is in the menu)."
