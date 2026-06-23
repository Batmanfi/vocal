#!/usr/bin/env bash
set -euo pipefail

# One-stop installer for Vocal.
#
# Works two ways:
#   1. From a checkout:   ./script/install.sh
#   2. Piped from GitHub: curl -fsSL https://raw.githubusercontent.com/Batmanfi/vocal/main/script/install.sh | bash
#
# It builds a fully self-contained Vocal.app (embedded Python + ML deps), installs it
# into /Applications, and launches it. After this you can delete any source checkout —
# the installed app is independent. The transcription model downloads once on first run.

REPO_URL="${VOCAL_REPO_URL:-https://github.com/Batmanfi/vocal.git}"
APP_NAME="Vocal"
DEST_APP="/Applications/$APP_NAME.app"

say() { printf '\033[1;36m%s\033[0m\n' "$*"; }
err() { printf '\033[1;31m%s\033[0m\n' "$*" >&2; }

# --- Preflight ------------------------------------------------------------------
if [ "$(uname -m)" != "arm64" ]; then
  err "Vocal needs an Apple Silicon Mac (M1 or newer). Detected: $(uname -m)."
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  err "git is required. Install the Xcode command-line tools: xcode-select --install"
  exit 1
fi
if ! command -v swift >/dev/null 2>&1 || ! xcode-select -p >/dev/null 2>&1; then
  err "The Xcode command-line tools are required to build Vocal."
  err "Run:  xcode-select --install   then re-run this installer."
  exit 1
fi

# --- Locate or fetch the source -------------------------------------------------
SELF_SRC="${BASH_SOURCE[0]:-$0}"
SELF_DIR="$(cd "$(dirname "$SELF_SRC")" 2>/dev/null && pwd || true)"
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/../Package.swift" ]; then
  SRC_DIR="$(cd "$SELF_DIR/.." && pwd)"
  say "==> Building from local checkout: $SRC_DIR"
else
  TMP_PARENT="$(mktemp -d)"
  SRC_DIR="$TMP_PARENT/vocal"
  say "==> Cloning $REPO_URL"
  git clone --depth 1 "$REPO_URL" "$SRC_DIR"
fi

# --- Build the self-contained bundle --------------------------------------------
"$SRC_DIR/script/package_app.sh"

# --- Install into /Applications -------------------------------------------------
say "==> Installing to $DEST_APP"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -f "parakeet_daemon.py" >/dev/null 2>&1 || true
sleep 1
rm -rf "$DEST_APP"
/usr/bin/ditto "$SRC_DIR/dist/$APP_NAME.app" "$DEST_APP"

# Re-sign at the final location so the designated requirement is intact there.
SIGNING_HASH="$(security find-identity -p codesigning 2>/dev/null \
  | grep "Vocal Self-Signed" | head -1 | awk '{print $2}')"
/usr/bin/codesign --force --deep --identifier "local.vocal.app" \
  --sign "${SIGNING_HASH:--}" "$DEST_APP" >/dev/null

say "==> Launching $APP_NAME"
/usr/bin/open "$DEST_APP"
sleep 2

echo
say "Done. Vocal is installed in /Applications."
echo "  • Open it any time from Spotlight (⌘Space → \"Vocal\") or Launchpad."
echo "  • First launch downloads the speech model (~2.3 GB) once, then runs offline."
echo "  • Grant Microphone, Input Monitoring, and Accessibility when prompted so it"
echo "    can record and paste at your cursor."
