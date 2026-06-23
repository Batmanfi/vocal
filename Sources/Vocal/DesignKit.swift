import AppKit

/// Shared visual building blocks tuned to match Superwhisper's look:
/// colored icon tiles, keycap chips, stat columns, rounded cards.
enum DesignKit {
    static let orange = NSColor(srgbRed: 0.97, green: 0.45, blue: 0.20, alpha: 1)
    static let blue   = NSColor(srgbRed: 0.20, green: 0.48, blue: 0.98, alpha: 1)
    static let purple = NSColor(srgbRed: 0.46, green: 0.40, blue: 0.95, alpha: 1)
    static let gray   = NSColor(srgbRed: 0.32, green: 0.32, blue: 0.34, alpha: 1)

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

        let cap = NSView()
        cap.translatesAutoresizingMaskIntoConstraints = false
        cap.wantsLayer = true
        cap.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        cap.layer?.cornerRadius = 5
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
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        v.layer?.cornerRadius = 12
        return v
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
    var isSelected = false { didSet { updateHighlight() } }

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
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

    private var isHovered = false { didSet { updateHighlight() } }
    private func updateHighlight() {
        let alpha: CGFloat = isSelected ? 0.13 : (isHovered ? 0.07 : 0.0)
        highlight.layer?.backgroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { action() }
}
