#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Vocal"
BUNDLE_ID="local.vocal.app"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

cd "$ROOT_DIR"

export HF_HUB_DISABLE_XET=1

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -f "$APP_BUNDLE/Contents/Resources/parakeet_daemon.py" >/dev/null 2>&1 || true
pkill -f "$ROOT_DIR/.build/.*/Vocal_Vocal.resources/parakeet_daemon.py" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/Sources/Vocal/Resources/parakeet_daemon.py" "$APP_RESOURCES/parakeet_daemon.py"

ICON_SRC="$ROOT_DIR/Sources/Vocal/Resources/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
  cp "$ICON_SRC" "$APP_RESOURCES/AppIcon.icns"
fi

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
  <string>Vocal records microphone audio while you hold Right Option for local speech transcription.</string>
</dict>
</plist>
PLIST

# Prefer a stable self-signed identity so the Accessibility/Input Monitoring grant
# survives rebuilds. Falls back to ad-hoc signing, which requires re-granting each build.
# The self-signed cert is untrusted, so it does NOT show under "find-identity -v"; we
# list without -v and sign by SHA-1 hash to avoid any name ambiguity. codesign signs
# fine with an untrusted identity, and the embedded designated requirement is what makes
# the TCC grant stable across rebuilds.
SIGNING_IDENTITY_NAME="Vocal Self-Signed"
SIGNING_HASH="$(security find-identity -p codesigning 2>/dev/null \
  | grep "$SIGNING_IDENTITY_NAME" | head -1 | awk '{print $2}')"
if [ -n "$SIGNING_HASH" ]; then
  echo "Signing with stable identity: $SIGNING_IDENTITY_NAME ($SIGNING_HASH)"
  /usr/bin/codesign --force --identifier "$BUNDLE_ID" \
    --sign "$SIGNING_HASH" "$APP_BUNDLE" >/dev/null
else
  echo "WARNING: no '$SIGNING_IDENTITY_NAME' identity found; signing ad-hoc."
  echo "         Accessibility will need re-granting after every rebuild."
  echo "         Run ./script/create_signing_cert.sh once to make the grant persistent."
  /usr/bin/codesign --force --identifier "$BUNDLE_ID" --sign - "$APP_BUNDLE" >/dev/null
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  stage|--stage)
    # Build + sign the bundle into dist/ without launching it (used by install.sh).
    :
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|stage|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
