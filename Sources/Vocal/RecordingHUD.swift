import AppKit

/// A live waveform view that scrolls input levels left-to-right.
final class WaveformView: NSView {
    private var levels: [CGFloat]
    private let barWidth: CGFloat
    private let barSpacing: CGFloat

    init(barCount: Int, barWidth: CGFloat, barSpacing: CGFloat) {
        self.levels = Array(repeating: 0, count: barCount)
        self.barWidth = barWidth
        self.barSpacing = barSpacing
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        levels = Array(repeating: 0, count: levels.count)
        needsDisplay = true
    }

    func push(_ level: CGFloat) {
        levels.removeFirst()
        levels.append(max(0, min(1, level)))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        let midY = bounds.midY
        let maxBar = bounds.height * 0.9
        let totalWidth = CGFloat(levels.count) * (barWidth + barSpacing) - barSpacing
        var x = (bounds.width - totalWidth) / 2
        NSColor.white.withAlphaComponent(0.92).setFill()
        for level in levels {
            let h = max(barWidth, level * maxBar)
            let rect = NSRect(x: x, y: midY - h / 2, width: barWidth, height: h)
            let path = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)
            path.fill()
            x += barWidth + barSpacing
        }
    }
}

/// A borderless, non-activating floating panel showing the live recording waveform.
/// It never takes key focus, so the focused app still receives the pasted text.
final class RecordingHUD {
    enum Style: String { case classic, mini, none }

    private var panel: NSPanel?
    private var waveform: WaveformView?
    private var currentStyle: Style = .none

    func show(style: Style) {
        guard style != .none else { hide(); return }
        if panel == nil || style != currentStyle {
            hide()
            build(style: style)
        }
        currentStyle = style
        waveform?.reset()
        positionPanel()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func addLevel(_ level: Float) {
        waveform?.push(CGFloat(level))
    }

    private func build(style: Style) {
        let size: NSSize = style == .classic ? NSSize(width: 300, height: 96) : NSSize(width: 168, height: 52)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let bg = NSView()
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        bg.layer?.cornerRadius = style == .classic ? 18 : 26
        bg.translatesAutoresizingMaskIntoConstraints = false

        let wave = WaveformView(
            barCount: style == .classic ? 46 : 20,
            barWidth: style == .classic ? 3 : 3,
            barSpacing: style == .classic ? 3 : 3
        )
        wave.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.addSubview(bg)
        bg.addSubview(wave)
        NSLayoutConstraint.activate([
            bg.topAnchor.constraint(equalTo: container.topAnchor),
            bg.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bg.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            wave.topAnchor.constraint(equalTo: bg.topAnchor, constant: style == .classic ? 14 : 10),
            wave.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: style == .classic ? -14 : -10),
            wave.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 16),
            wave.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -16),
        ])

        panel.contentView = container
        self.panel = panel
        self.waveform = wave
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.minY + 110
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
