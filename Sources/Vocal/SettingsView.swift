import AppKit

/// Settings / Configuration pane: model & device info plus the core controls.
final class SettingsView: NSView {
    var onChangeShortcut: (() -> Void)?
    var onChangeToggleShortcut: (() -> Void)?
    var onOpenAccessibility: (() -> Void)?
    var onToggleLogin: (() -> Void)?
    var onSetRecordingWindow: ((String) -> Void)?
    var onSetFormatNumbers: ((Bool) -> Void)?

    private let modelValue = valueLabel()
    private let deviceValue = valueLabel()
    private let shortcutValue = valueLabel()
    private let toggleValue = valueLabel()
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let numbersCheckbox = NSButton(checkboxWithTitle: "Convert spoken numbers to digits (e.g. \"twenty\" → 20)", target: nil, action: nil)
    private let windowSegmented = NSSegmentedControl(labels: ["Classic", "Mini", "None"], trackingMode: .selectOne, target: nil, action: nil)
    private let windowStyles = ["classic", "mini", "none"]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    func updateModel(_ s: String) { modelValue.stringValue = s }
    func updateDevice(_ s: String) { deviceValue.stringValue = s }
    func updateShortcut(_ s: String) { shortcutValue.stringValue = s }
    func updateToggleShortcut(_ s: String) { toggleValue.stringValue = s }
    func updateLoginState(_ enabled: Bool) { loginCheckbox.state = enabled ? .on : .off }
    func updateFormatNumbers(_ enabled: Bool) { numbersCheckbox.state = enabled ? .on : .off }
    func updateRecordingWindow(_ style: String) {
        windowSegmented.selectedSegment = windowStyles.firstIndex(of: style) ?? 0
    }

    private static func valueLabel() -> NSTextField {
        let l = NSTextField(labelWithString: "—")
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.lineBreakMode = .byTruncatingMiddle
        return l
    }

    private func build() {
        let title = NSTextField(labelWithString: "Settings")
        title.font = .systemFont(ofSize: 22, weight: .bold)

        // Shortcuts card
        let shortcutsCard = DesignKit.card()
        let shortcutsStack = NSStackView(views: [
            shortcutRow("Hold to talk", shortcutValue, action: #selector(changeShortcut)),
            divider(),
            shortcutRow("Toggle (continuous)", toggleValue, action: #selector(changeToggleShortcut)),
        ])
        shortcutsStack.orientation = .vertical
        shortcutsStack.alignment = .leading
        shortcutsStack.spacing = 10
        shortcutsStack.translatesAutoresizingMaskIntoConstraints = false
        shortcutsCard.addSubview(shortcutsStack)
        pin(shortcutsStack, in: shortcutsCard)

        // Recording window picker
        let windowLabel = DesignKit.sectionLabel("Recording window")
        windowSegmented.target = self
        windowSegmented.action = #selector(windowChanged)
        windowSegmented.translatesAutoresizingMaskIntoConstraints = false

        // Numbers + login toggles
        numbersCheckbox.target = self
        numbersCheckbox.action = #selector(numbersChanged)
        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)

        let accessButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAccess))

        // Info card
        let infoCard = DesignKit.card()
        let infoStack = NSStackView(views: [
            infoRow("Model", modelValue),
            infoRow("Device", deviceValue),
            infoRow("Config", { let l = SettingsView.valueLabel(); l.stringValue = VocalConfig.configURL.path; return l }()),
            infoRow("Version", { let l = SettingsView.valueLabel(); l.stringValue = "1.0"; return l }()),
        ])
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 10
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        infoCard.addSubview(infoStack)
        pin(infoStack, in: infoCard)

        let column = NSStackView(views: [
            title,
            shortcutsCard,
            windowLabel,
            windowSegmented,
            numbersCheckbox,
            loginCheckbox,
            accessButton,
            DesignKit.sectionLabel("About"),
            infoCard,
        ])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 14
        column.setCustomSpacing(8, after: windowLabel)
        column.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(column)
        scroll.documentView = doc
        addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),

            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),

            column.topAnchor.constraint(equalTo: doc.topAnchor, constant: 24),
            column.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 28),
            column.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -24),
            column.bottomAnchor.constraint(lessThanOrEqualTo: doc.bottomAnchor, constant: -20),

            shortcutsCard.widthAnchor.constraint(equalTo: column.widthAnchor),
            infoCard.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
    }

    private func pin(_ inner: NSView, in card: NSView) {
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
    }

    private func divider() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        line.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        return line
    }

    private func shortcutRow(_ name: String, _ value: NSTextField, action: Selector) -> NSView {
        let key = NSTextField(labelWithString: name)
        key.font = .systemFont(ofSize: 13)
        key.textColor = .secondaryLabelColor
        key.translatesAutoresizingMaskIntoConstraints = false
        key.widthAnchor.constraint(equalToConstant: 150).isActive = true
        value.translatesAutoresizingMaskIntoConstraints = false
        let button = NSButton(title: "Change…", target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [key, value, button])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        return row
    }

    private func infoRow(_ name: String, _ value: NSTextField) -> NSView {
        let key = NSTextField(labelWithString: name)
        key.font = .systemFont(ofSize: 13)
        key.textColor = .secondaryLabelColor
        key.translatesAutoresizingMaskIntoConstraints = false
        key.widthAnchor.constraint(equalToConstant: 84).isActive = true
        value.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: [key, value])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .firstBaseline
        return row
    }

    @objc private func changeShortcut() { onChangeShortcut?() }
    @objc private func changeToggleShortcut() { onChangeToggleShortcut?() }
    @objc private func openAccess() { onOpenAccessibility?() }
    @objc private func toggleLogin() { onToggleLogin?() }
    @objc private func numbersChanged() { onSetFormatNumbers?(numbersCheckbox.state == .on) }
    @objc private func windowChanged() {
        let idx = windowSegmented.selectedSegment
        guard idx >= 0, idx < windowStyles.count else { return }
        onSetRecordingWindow?(windowStyles[idx])
    }
}
