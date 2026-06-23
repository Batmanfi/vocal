import AppKit

/// Builds the menu-bar status glyph from the bundled `MenuGlyph.svg` (the Vocal
/// microphone silhouette) and renders it per app state — replacing the old emoji.
///
/// Idle uses a monochrome *template* image, so it adapts to light/dark menu bars
/// like every other system item. Active states return a color-tinted copy
/// (red while recording, accent while transcribing, dimmed while loading, red on
/// error). The gentle pulse for recording/transcribing is driven separately in
/// the app delegate via the status button's `alphaValue`.
enum MenuBarIcon {
    /// Point size of the menu-bar glyph. ~18pt matches the system status item height.
    private static let glyphSize = NSSize(width: 18, height: 18)

    private static let baseTemplate: NSImage? = loadGlyph()

    static func image(for state: AppState) -> NSImage? {
        guard let base = baseTemplate else { return nil }
        switch state {
        case .idle:
            return base // template; the menu bar tints it for us
        case .loading:
            return tinted(base, .tertiaryLabelColor)
        case .recording:
            return tinted(base, .systemRed)
        case .transcribing:
            return tinted(base, .controlAccentColor)
        case .error:
            return tinted(base, .systemRed)
        }
    }

    /// A template copy of the glyph at `size`, for an in-window `NSImageView`. Pair it
    /// with `tintColor(for:)` via the image view's `contentTintColor` — because the tint
    /// colors are semantic/dynamic, the glyph recolors automatically when the theme changes.
    static func templateGlyph(size: CGFloat) -> NSImage? {
        guard let base = baseTemplate else { return nil }
        let target = NSSize(width: size, height: size)
        let out = NSImage(size: target)
        out.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: target))
        out.unlockFocus()
        out.isTemplate = true
        return out
    }

    /// In-window tint for a state. Idle uses `.labelColor` so it adapts to light/dark;
    /// active states match the menu-bar colors.
    static func tintColor(for state: AppState) -> NSColor {
        switch state {
        case .idle: return .labelColor
        case .loading: return .tertiaryLabelColor
        case .recording: return .systemRed
        case .transcribing: return .controlAccentColor
        case .error: return .systemRed
        }
    }

    private static func loadGlyph() -> NSImage? {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("MenuGlyph.svg"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/MenuGlyph.svg"),
        ]
        let url = candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        image.size = glyphSize
        image.isTemplate = true
        return image
    }

    /// Re-color the glyph by filling its opaque (alpha) area with `color`.
    private static func tinted(_ base: NSImage, _ color: NSColor) -> NSImage {
        let image = NSImage(size: base.size)
        image.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: base.size))
        color.set()
        NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
