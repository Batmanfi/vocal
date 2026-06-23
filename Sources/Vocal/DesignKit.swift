import AppKit

/// Shared visual building blocks tuned to match Superwhisper's look:
/// colored icon tiles, keycap chips, stat columns, rounded cards.
enum DesignKit {
    static let orange = NSColor(srgbRed: 0.97, green: 0.45, blue: 0.20, alpha: 1)
    static let blue   = NSColor(srgbRed: 0.20, green: 0.48, blue: 0.98, alpha: 1)
    static let purple = NSColor(srgbRed: 0.46, green: 0.40, blue: 0.95, alpha: 1)
    static let gray   = NSColor(srgbRed: 0.32, green: 0.32, blue: 0.34, alpha: 1)

    /// Returns true when the view's current appearance is dark.
    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Translucent overlay that reads correctly in both themes: a white wash on dark
    /// backgrounds, a black wash on light ones (black reads stronger, so it's eased
    /// down a touch). Resolve this against a view's `effectiveAppearance`.
    static func overlayCGColor(alpha: CGFloat, appearance: NSAppearance) -> CGColor {
        let dark = isDark(appearance)
        let base: NSColor = dark ? .white : .black
        return base.withAlphaComponent(dark ? alpha : alpha * 0.8).cgColor
    }

    static func symbolImage(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .semibold, color: NSColor = .white) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        return base.withSymbolConfiguration(config)
    }

    /// Rounded colored tile with a white SF Symbol — the sidebar item icon style.
    static func iconTile(symbol: String, color: NSColor, size: CGFloat = 26, symbolSize: CGFloat = 13) -> NSView {
        let tile = NSView()
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.wantsLayer = true
        tile.layer?.backgroundColor = color.cgColor
        tile.layer?.cornerRadius = 6
        tile.widthAnchor.constraint(equalToConstant: size).isActive = true
        tile.heightAnchor.constraint(equalToConstant: size).isActive = true

        let iv = NSImageView(image: symbolImage(symbol, pointSize: symbolSize) ?? NSImage())
        iv.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
        ])
        return tile
    }

    /// A small keyboard-key chip, e.g. "⌥" or "Space".
    static func keyCap(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let cap = OverlayView(alpha: 0.10, cornerRadius: 5)
        cap.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: cap.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: cap.bottomAnchor, constant: -3),
            label.leadingAnchor.constraint(equalTo: cap.leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: cap.trailingAnchor, constant: -7),
            cap.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
        ])
        return cap
    }

    /// Renders a hotkey as a row of keycap chips (⌥ + Space, etc.).
    static func keyCapRow(for spec: HotkeySpec) -> NSView {
        var caps: [NSView] = []
        if spec.isModifierOnly {
            caps.append(keyCap(spec.displayString))
        } else {
            let flags = CGEventFlags(rawValue: spec.modifierFlags)
            if flags.contains(.maskControl) { caps.append(keyCap("⌃")) }
            if flags.contains(.maskAlternate) { caps.append(keyCap("⌥")) }
            if flags.contains(.maskShift) { caps.append(keyCap("⇧")) }
            if flags.contains(.maskCommand) { caps.append(keyCap("⌘")) }
            if flags.contains(.maskSecondaryFn) { caps.append(keyCap("fn")) }
            caps.append(keyCap(HotkeySpec.keyName(forKeyCode: spec.keyCode)))
        }
        let stack = NSStackView(views: caps)
        stack.orientation = .horizontal
        stack.spacing = 5
        return stack
    }

    static func card() -> NSView {
        OverlayView(alpha: 0.05, cornerRadius: 12)
    }

    static func sectionLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return l
    }
}

/// A view that calls a closure when clicked and shows a hover/selected highlight.
class ClickableRow: NSView {
    private let action: () -> Void
    let highlight = NSView()
    private var trackingArea: NSTrackingArea?
    var isSelected = false { didSet { applyAppearanceColors() } }

    /// Optional always-on translucent fill behind the row (used by the history cards).
    /// 0 = transparent (sidebar items rely on the hover/selected highlight only).
    var baseOverlayAlpha: CGFloat = 0 { didSet { applyAppearanceColors() } }
    var cornerRadius: CGFloat = 0 { didSet { layer?.cornerRadius = cornerRadius } }

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = 8
        highlight.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlight, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            highlight.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private var isHovered = false { didSet { applyAppearanceColors() } }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceColors()
    }

    private func applyAppearanceColors() {
        if baseOverlayAlpha > 0 {
            layer?.backgroundColor = DesignKit.overlayCGColor(alpha: baseOverlayAlpha, appearance: effectiveAppearance)
        }
        let alpha: CGFloat = isSelected ? 0.13 : (isHovered ? 0.07 : 0.0)
        highlight.layer?.backgroundColor = alpha > 0
            ? DesignKit.overlayCGColor(alpha: alpha, appearance: effectiveAppearance)
            : NSColor.clear.cgColor
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { action() }
}

/// Layer-backed translucent surface (cards, key caps) whose fill adapts to the
/// light/dark theme and re-resolves on appearance change, so the toggle updates it live.
final class OverlayView: NSView {
    private let overlayAlpha: CGFloat

    init(alpha: CGFloat, cornerRadius: CGFloat) {
        self.overlayAlpha = alpha
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        applyOverlay()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyOverlay()
    }

    private func applyOverlay() {
        layer?.backgroundColor = DesignKit.overlayCGColor(alpha: overlayAlpha, appearance: effectiveAppearance)
    }
}
