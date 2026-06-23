#!/usr/bin/env bash
set -euo pipefail

# Generates Sources/Vocal/Resources/AppIcon.icns — a violet squircle with a white
# microphone glyph — so Vocal looks like a real app in Launchpad / Dock / Finder.
# Run this once (or whenever you want to regenerate). To use a custom image instead,
# replace AppIcon.icns with your own (1024x1024 source recommended).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES_DIR="$ROOT_DIR/Sources/Vocal/Resources"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SWIFT_SRC="$TMP/icon.swift"
cat >"$SWIFT_SRC" <<'SWIFT'
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outDir = CommandLine.arguments[1]

func makeIcon(size: Int) -> Data? {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    // Squircle background with a small margin, like a standard macOS icon tile.
    let margin = s * 0.08
    let rect = NSRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let radius = rect.width * 0.2237
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.addClip()

    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.49, green: 0.36, blue: 1.0, alpha: 1.0),
                              ending: NSColor(calibratedRed: 0.29, green: 0.18, blue: 0.84, alpha: 1.0))
    gradient?.draw(in: rect, angle: -90)

    // White microphone glyph centered.
    let glyphSize = s * 0.46
    let glyphRect = NSRect(x: (s - glyphSize) / 2, y: (s - glyphSize) / 2, width: glyphSize, height: glyphSize)
    if let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: glyphSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: .white))
        if let white = mic.withSymbolConfiguration(config) {
            white.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        } else {
            NSColor.white.set(); mic.draw(in: glyphRect)
        }
    }

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
swift "$SWIFT_SRC" "$PNG_DIR"

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
