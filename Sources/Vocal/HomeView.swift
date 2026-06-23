import AppKit
import AVFoundation

/// Superwhisper-style Home: top bar (status + mic device), an "All time" stats card,
/// and a "Get started" action list.
final class HomeView: NSView {
    var onChangeShortcut: (() -> Void)?
    var onOpenAccessibility: (() -> Void)?
    var onToggleLogin: (() -> Void)?

    private let statusLabel = NSTextField(labelWithString: "Loading…")
    private let deviceLabel = NSTextField(labelWithString: "")

    private let wpmValue = NSTextField(labelWithString: "0")
    private let wordsValue = NSTextField(labelWithString: "0")
    private let appsValue = NSTextField(labelWithString: "0")
    private let avgValue = NSTextField(labelWithString: "0")

    private let dictateSubtitle = NSTextField(labelWithString: "")
    private let keycapContainer = NSView()
    private let loginStateLabel = NSTextField(labelWithString: "Off")

    private var shortcut: HotkeySpec = .rightOption

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        reloadStats()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Updates from the controller

    func updateStatus(icon: String, text: String) {
        statusLabel.stringValue = "\(icon)  \(text)"
    }
    func updateShortcut(_ spec: HotkeySpec) {
        shortcut = spec
        dictateSubtitle.stringValue = "Hold \(spec.displayString) and speak; release to insert text."
        rebuildKeycaps()
    }
    func updateLoginState(_ enabled: Bool) {
        loginStateLabel.stringValue = enabled ? "On" : "Off"
        loginStateLabel.textColor = enabled ? DesignKit.blue : .secondaryLabelColor
    }

    func reloadStats() {
        let entries = HistoryStore.shared.entries
        let words = entries.reduce(0) { $0 + $1.text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count }
        let apps = Set(entries.compactMap { $0.appName }).count
        wordsValue.stringValue = numberString(words)
        wpmValue.stringValue = numberString(entries.count)
        appsValue.stringValue = numberString(apps)
        avgValue.stringValue = entries.isEmpty ? "0" : numberString(words / max(entries.count, 1))
    }

    private func numberString(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    // MARK: - Build

    private func build() {
        // Top bar
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        deviceLabel.stringValue = AVCaptureDevice.default(for: .audio)?.localizedName ?? "Microphone"
        deviceLabel.font = .systemFont(ofSize: 13)
        deviceLabel.textColor = .secondaryLabelColor
        deviceLabel.alignment = .right
        deviceLabel.lineBreakMode = .byTruncatingTail
        deviceLabel.translatesAutoresizingMaskIntoConstraints = false
        let micIcon = NSImageView(image: DesignKit.symbolImage("mic.fill", pointSize: 12, color: .secondaryLabelColor) ?? NSImage())
        micIcon.translatesAutoresizingMaskIntoConstraints = false

        addSubview(statusLabel)
        addSubview(deviceLabel)
        addSubview(micIcon)

        // Stats card
        let statsCard = DesignKit.card()
        let allTime = NSTextField(labelWithString: "All time")
        allTime.font = .systemFont(ofSize: 14, weight: .semibold)
        allTime.translatesAutoresizingMaskIntoConstraints = false
        let stats = NSStackView(views: [
            statColumn(wordsValue, "Words"),
            statColumn(wpmValue, "Transcriptions"),
            statColumn(appsValue, "Apps used"),
            statColumn(avgValue, "Avg words"),
        ])
        stats.orientation = .horizontal
        stats.distribution = .fillEqually
        stats.alignment = .top
        stats.translatesAutoresizingMaskIntoConstraints = false
        statsCard.addSubview(allTime)
        statsCard.addSubview(stats)
        NSLayoutConstraint.activate([
            allTime.topAnchor.constraint(equalTo: statsCard.topAnchor, constant: 16),
            allTime.leadingAnchor.constraint(equalTo: statsCard.leadingAnchor, constant: 20),
            stats.topAnchor.constraint(equalTo: allTime.bottomAnchor, constant: 12),
            stats.leadingAnchor.constraint(equalTo: statsCard.leadingAnchor, constant: 20),
            stats.trailingAnchor.constraint(equalTo: statsCard.trailingAnchor, constant: -20),
            stats.bottomAnchor.constraint(equalTo: statsCard.bottomAnchor, constant: -18),
        ])

        // Get started rows
        let getStarted = DesignKit.sectionLabel("Get started")
        getStarted.translatesAutoresizingMaskIntoConstraints = false

        dictateSubtitle.stringValue = "Hold the shortcut and speak; release to insert text."
        let dictateRow = actionRow(symbol: "mic.fill", title: "Dictate", subtitle: dictateSubtitle, trailing: keycapContainer, action: {})
        let shortcutRow = actionRow(symbol: "keyboard", title: "Change your shortcut", subtitle: makeSub("Pick the key you hold to dictate."), trailing: chevron(), action: { [weak self] in self?.onChangeShortcut?() })
        let accessRow = actionRow(symbol: "lock.shield", title: "Grant Accessibility", subtitle: makeSub("Allow Vocal to paste text at your cursor."), trailing: chevron(), action: { [weak self] in self?.onOpenAccessibility?() })
        let loginRow = actionRow(symbol: "power", title: "Launch at login", subtitle: makeSub("Start Vocal automatically when you log in."), trailing: loginStateLabel, action: { [weak self] in self?.onToggleLogin?() })
        loginStateLabel.font = .systemFont(ofSize: 13, weight: .medium)
        loginStateLabel.textColor = .secondaryLabelColor

        let rows = NSStackView(views: [dictateRow, shortcutRow, accessRow, loginRow])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 2
        rows.translatesAutoresizingMaskIntoConstraints = false

        addSubview(statsCard)
        addSubview(getStarted)
        addSubview(rows)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),

            deviceLabel.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            deviceLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            deviceLabel.leadingAnchor.constraint(greaterThanOrEqualTo: statusLabel.trailingAnchor, constant: 12),
            micIcon.centerYAnchor.constraint(equalTo: deviceLabel.centerYAnchor),
            micIcon.trailingAnchor.constraint(equalTo: deviceLabel.leadingAnchor, constant: -6),

            statsCard.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 22),
            statsCard.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            statsCard.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            getStarted.topAnchor.constraint(equalTo: statsCard.bottomAnchor, constant: 28),
            getStarted.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),

            rows.topAnchor.constraint(equalTo: getStarted.bottomAnchor, constant: 10),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
        ])

        rebuildKeycaps()
    }

    private func statColumn(_ value: NSTextField, _ caption: String) -> NSView {
        value.font = .systemFont(ofSize: 22, weight: .semibold)
        value.translatesAutoresizingMaskIntoConstraints = false
        let cap = NSTextField(labelWithString: caption)
        cap.font = .systemFont(ofSize: 12)
        cap.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [value, cap])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        return stack
    }

    private func makeSub(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 13)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func chevron() -> NSView {
        NSImageView(image: DesignKit.symbolImage("chevron.right", pointSize: 11, weight: .semibold, color: .tertiaryLabelColor) ?? NSImage())
    }

    private func actionRow(symbol: String, title: String, subtitle: NSTextField, trailing: NSView, action: @escaping () -> Void) -> NSView {
        let row = ClickableRow(action: action)

        let glyph = NSImageView(image: DesignKit.symbolImage(symbol, pointSize: 16, weight: .regular, color: .secondaryLabelColor) ?? NSImage())
        glyph.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        trailing.translatesAutoresizingMaskIntoConstraints = false
        trailing.setContentHuggingPriority(.required, for: .horizontal)

        row.addSubview(glyph)
        row.addSubview(titleLabel)
        row.addSubview(subtitle)
        row.addSubview(trailing)

        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            glyph.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            glyph.widthAnchor.constraint(equalToConstant: 22),
            glyph.topAnchor.constraint(equalTo: row.topAnchor, constant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 11),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -12),

            subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitle.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -12),

            trailing.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            trailing.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func rebuildKeycaps() {
        keycapContainer.subviews.forEach { $0.removeFromSuperview() }
        let caps = DesignKit.keyCapRow(for: shortcut)
        caps.translatesAutoresizingMaskIntoConstraints = false
        keycapContainer.addSubview(caps)
        NSLayoutConstraint.activate([
            caps.topAnchor.constraint(equalTo: keycapContainer.topAnchor),
            caps.bottomAnchor.constraint(equalTo: keycapContainer.bottomAnchor),
            caps.leadingAnchor.constraint(equalTo: keycapContainer.leadingAnchor),
            caps.trailingAnchor.constraint(equalTo: keycapContainer.trailingAnchor),
        ])
    }
}
