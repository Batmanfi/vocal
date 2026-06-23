#!/usr/bin/env bash
set -euo pipefail

# Builds a fully self-contained Vocal.app into dist/. The bundle embeds its own
# relocatable Python 3.11 (from python-build-standalone) with parakeet-mlx and all
# ML dependencies installed inside Contents/Resources/python. The result needs no
# project folder, no virtualenv, and no system Python — it can be copied to
# /Applications and the source checkout deleted.
#
# The 2.3 GB Parakeet model is NOT bundled; it downloads once on first launch into
# the Hugging Face cache, after which the app runs fully offline.

APP_NAME="Vocal"
BUNDLE_ID="local.vocal.app"
MIN_SYSTEM_VERSION="13.0"
PY_SERIES="3.11"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
PY_DEST="$APP_RESOURCES/python"
CACHE_DIR="${VOCAL_BUILD_CACHE:-$HOME/.cache/vocal-build}"

cd "$ROOT_DIR"
export HF_HUB_DISABLE_XET=1

if [ "$(uname -m)" != "arm64" ]; then
  echo "ERROR: Vocal requires an Apple Silicon Mac (arm64). Detected: $(uname -m)." >&2
  exit 1
fi

echo "==> Stopping any running instances"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -f "parakeet_daemon.py" >/dev/null 2>&1 || true

echo "==> Building Swift app (release)"
swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "==> Assembling app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/Sources/Vocal/Resources/parakeet_daemon.py" "$APP_RESOURCES/parakeet_daemon.py"
cp "$ROOT_DIR/Sources/Vocal/Resources/MenuGlyph.svg" "$APP_RESOURCES/MenuGlyph.svg"
ICON_SRC="$ROOT_DIR/Sources/Vocal/Resources/AppIcon.icns"
[ -f "$ICON_SRC" ] && cp "$ICON_SRC" "$APP_RESOURCES/AppIcon.icns"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Vocal records microphone audio while you hold your shortcut for local speech transcription.</string>
</dict>
</plist>
PLIST

# --- Embed a relocatable Python interpreter -------------------------------------
echo "==> Resolving standalone Python ($PY_SERIES, arm64)"
PY_URL="${VOCAL_PYTHON_URL:-}"
if [ -z "$PY_URL" ]; then
  PY_URL="$(curl -fsSL https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest \
    | /usr/bin/python3 -c "
import sys, json
d = json.load(sys.stdin)
for a in d['assets']:
    n = a['name']
    if n.startswith('cpython-$PY_SERIES.') and n.endswith('-aarch64-apple-darwin-install_only.tar.gz'):
        print(a['browser_download_url']); break
")"
fi
if [ -z "$PY_URL" ]; then
  echo "ERROR: could not resolve a standalone Python download URL." >&2
  exit 1
fi

mkdir -p "$CACHE_DIR"
PY_TARBALL="$CACHE_DIR/$(basename "${PY_URL%%\?*}")"
if [ ! -f "$PY_TARBALL" ]; then
  echo "==> Downloading $(basename "$PY_TARBALL")"
  curl -fSL "$PY_URL" -o "$PY_TARBALL.partial"
  mv "$PY_TARBALL.partial" "$PY_TARBALL"
else
  echo "==> Using cached $(basename "$PY_TARBALL")"
fi

echo "==> Unpacking Python into the bundle"
rm -rf "$PY_DEST"
mkdir -p "$PY_DEST"
# install_only tarballs extract to a top-level "python/" directory.
tar -xzf "$PY_TARBALL" -C "$APP_RESOURCES"
PY_BIN="$PY_DEST/bin/python3"
[ -x "$PY_BIN" ] || { echo "ERROR: embedded python missing at $PY_BIN" >&2; exit 1; }

echo "==> Installing ML dependencies into the embedded Python (this takes a few minutes)"
"$PY_BIN" -m pip install --upgrade --no-warn-script-location pip >/dev/null
"$PY_BIN" -m pip install --no-warn-script-location -r "$ROOT_DIR/requirements.txt"

echo "==> Trimming the bundle"
# Tooling we don't need at runtime, and caches that bloat the bundle.
"$PY_BIN" -m pip uninstall -y pip setuptools wheel >/dev/null 2>&1 || true
find "$PY_DEST" -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
find "$PY_DEST" -type d -name "tests" -prune -exec rm -rf {} + 2>/dev/null || true
rm -rf "$PY_DEST/lib/python$PY_SERIES/test" "$PY_DEST/lib/python$PY_SERIES/idlelib" \
       "$PY_DEST/lib/python$PY_SERIES/lib2to3" "$PY_DEST/lib/python$PY_SERIES/ensurepip" 2>/dev/null || true

# --- Sign ------------------------------------------------------------------------
SIGNING_IDENTITY_NAME="Vocal Self-Signed"
SIGNING_HASH="$(security find-identity -p codesigning 2>/dev/null \
  | grep "$SIGNING_IDENTITY_NAME" | head -1 | awk '{print $2}')"
if [ -n "$SIGNING_HASH" ]; then
  SIGN_ARG="$SIGNING_HASH"
  echo "==> Signing with stable identity ($SIGNING_IDENTITY_NAME)"
else
  SIGN_ARG="-"
  echo "==> Signing ad-hoc (run ./script/create_signing_cert.sh once for a stable identity)"
fi
# Sign the whole tree, inner code first, so every embedded .dylib/.so is covered.
/usr/bin/codesign --force --deep --identifier "$BUNDLE_ID" --sign "$SIGN_ARG" "$APP_BUNDLE" >/dev/null

APP_SIZE="$(du -sh "$APP_BUNDLE" | awk '{print $1}')"
echo "==> Done: $APP_BUNDLE ($APP_SIZE)"
