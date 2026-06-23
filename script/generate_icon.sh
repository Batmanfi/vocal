#!/usr/bin/env bash
set -euo pipefail

# Generates Sources/Vocal/Resources/AppIcon.icns from the source artwork at
# Sources/Vocal/Resources/AppIconSource.png (1000x1000 recommended).
#
# The source is full-bleed, so we mask it into the standard macOS "squircle" tile
# with a transparent margin — this makes Vocal sit correctly next to other apps in
# the Dock / Launchpad / Finder. To use full-square corners instead, set
# VOCAL_ICON_SQUIRCLE=0.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES_DIR="$ROOT_DIR/Sources/Vocal/Resources"
SRC_PNG="$RES_DIR/AppIconSource.png"
SQUIRCLE="${VOCAL_ICON_SQUIRCLE:-1}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ -f "$SRC_PNG" ] || { echo "ERROR: missing $SRC_PNG" >&2; exit 1; }

SWIFT_SRC="$TMP/icon.swift"
cat >"$SWIFT_SRC" <<'SWIFT'
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let srcPath = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]
let squircle = CommandLine.arguments[3] != "0"

guard let source = NSImage(contentsOfFile: srcPath) else {
    FileHandle.standardError.write("Could not load \(srcPath)\n".data(using: .utf8)!)
    exit(1)
}

func makeIcon(size: Int) -> Data? {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    // Standard macOS icon grid: the tile occupies ~80% of the canvas, leaving a
    // transparent margin, with a continuous rounded-rect (squircle) corner.
    let margin = squircle ? s * 0.0977 : 0
    let rect = NSRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    if squircle {
        let radius = rect.width * 0.2237
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    }
    source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for size in sizes {
    if let data = makeIcon(size: size) {
        try? data.write(to: URL(fileURLWithPath: "\(outDir)/\(size).png"))
    }
}
SWIFT

PNG_DIR="$TMP/png"
mkdir -p "$PNG_DIR"
swift "$SWIFT_SRC" "$SRC_PNG" "$PNG_DIR" "$SQUIRCLE"

# Assemble the .iconset (Apple's required name/size layout) and convert to .icns.
ICONSET="$TMP/Vocal.iconset"
mkdir -p "$ICONSET"
cp "$PNG_DIR/16.png"   "$ICONSET/icon_16x16.png"
cp "$PNG_DIR/32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$PNG_DIR/32.png"   "$ICONSET/icon_32x32.png"
cp "$PNG_DIR/64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$PNG_DIR/128.png"  "$ICONSET/icon_128x128.png"
cp "$PNG_DIR/256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$PNG_DIR/256.png"  "$ICONSET/icon_256x256.png"
cp "$PNG_DIR/512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$PNG_DIR/512.png"  "$ICONSET/icon_512x512.png"
cp "$PNG_DIR/1024.png" "$ICONSET/icon_512x512@2x.png"

mkdir -p "$RES_DIR"
/usr/bin/iconutil -c icns "$ICONSET" -o "$RES_DIR/AppIcon.icns"
echo "Wrote $RES_DIR/AppIcon.icns"
