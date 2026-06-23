import AppKit

/// The main app window, styled to match Superwhisper: a translucent dark sidebar
/// with colored icon tiles and a content area that swaps Home / History / Settings.
final class MainWindowController: NSObject, NSWindowDelegate {
    enum Section: Int { case home, history, settings }

    private var window: NSWindow?
    private var contentContainer: NSView!
    private var homeView: HomeView!
    private var historyView: HistoryCardsView!
    private var settingsView: SettingsView!
    private var sidebarItems: [(view: ClickableRow, section: Section)] = []

    // Wired by AppDelegate.
    var onChangeShortcut: (() -> Void)?
    var onChangeToggleShortcut: (() -> Void)?
    var onOpenAccessibility: (() -> Void)?
    var onToggleLogin: (() -> Void)?
    var onSetRecordingWindow: ((String) -> Void)?
    var onSetFormatNumbers: ((Bool) -> Void)?
    var onSetAppearance: ((String) -> Void)?
    var loginEnabledProvider: (() -> Bool)?

    // Cached state so a freshly built window shows current values.
    private var statusState: AppState = .loading
    private var statusText = "Loading model..."
    private var model = ""
    private var device = "loading…"
    private var shortcut: HotkeySpec = .rightOption
    private var toggleShortcut = ""
    private var recordingWindow = "classic"
    private var formatNumbers = true
    private var appearance = "system"

    func show(section: Section = .home) {
        let firstBuild = window == nil
        if firstBuild { buildWindow() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if firstBuild { window?.center() }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        select(section)
        homeView.reloadStats()
        historyView.reload()
    }

    // MARK: - Updates

    func updateStatus(state: AppState, text: String) {
        statusState = state; statusText = text
        homeView?.updateStatus(state: state, text: text)
        homeView?.reloadStats()
    }
    func updateModel(_ m: String) { model = m; settingsView?.updateModel(m) }
    func updateDevice(_ d: String) { device = d; settingsView?.updateDevice(d) }
    func updateShortcut(_ spec: HotkeySpec) {
        shortcut = spec
        homeView?.updateShortcut(spec)
        settingsView?.updateShortcut(spec.displayString)
    }
    func updateLastEvent(_ message: String) { /* surfaced via the menu bar item */ }
    func updateToggleShortcut(_ s: String) { toggleShortcut = s; settingsView?.updateToggleShortcut(s) }
    func updateRecordingWindow(_ s: String) { recordingWindow = s; settingsView?.updateRecordingWindow(s) }
    func updateFormatNumbers(_ enabled: Bool) { formatNumbers = enabled; settingsView?.updateFormatNumbers(enabled) }
    func updateAppearance(_ mode: String) { appearance = mode; settingsView?.updateAppearance(mode) }
    func refreshLoginState() {
        let enabled = loginEnabledProvider?() ?? false
        homeView?.updateLoginState(enabled)
        settingsView?.updateLoginState(enabled)
    }

    // MARK: - Window

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Vocal"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 480)
        // Appearance follows NSApp.appearance, which AppDelegate sets from config
        // (system / light / dark). No per-window override here.
        window.delegate = self
        window.isMovableByWindowBackground = true

        let root = NSView()

        // Sidebar (translucent)
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let home = makeSidebarItem("Home", symbol: "house.fill", color: DesignKit.orange, section: .home)
        let history = makeSidebarItem("History", symbol: "clock.arrow.circlepath", color: DesignKit.purple, section: .history)
        let settings = makeSidebarItem("Settings", symbol: "gearshape.fill", color: DesignKit.gray, section: .settings)

        let topGroup = NSStackView(views: [home, history])
        topGroup.orientation = .vertical
        topGroup.alignment = .leading
        topGroup.spacing = 2
        topGroup.translatesAutoresizingMaskIntoConstraints = false

        let bottomGroup = NSStackView(views: [settings])
        bottomGroup.orientation = .vertical
        bottomGroup.alignment = .leading
        bottomGroup.spacing = 2
        bottomGroup.translatesAutoresizingMaskIntoConstraints = false

        sidebar.addSubview(topGroup)
        sidebar.addSubview(bottomGroup)

        // Content
        let content = NSVisualEffectView()
        content.material = .underWindowBackground
        content.blendingMode = .behindWindow
        content.state = .active
        content.translatesAutoresizingMaskIntoConstraints = false
        contentContainer = content

        homeView = HomeView()
        homeView.translatesAutoresizingMaskIntoConstraints = false
        homeView.onChangeShortcut = { [weak self] in self?.onChangeShortcut?() }
        homeView.onOpenAccessibility = { [weak self] in self?.onOpenAccessibility?() }
        homeView.onToggleLogin = { [weak self] in self?.onToggleLogin?() }

        historyView = HistoryCardsView()
        historyView.translatesAutoresizingMaskIntoConstraints = false

        settingsView = SettingsView()
        settingsView.translatesAutoresizingMaskIntoConstraints = false
        settingsView.onChangeShortcut = { [weak self] in self?.onChangeShortcut?() }
        settingsView.onChangeToggleShortcut = { [weak self] in self?.onChangeToggleShortcut?() }
        settingsView.onOpenAccessibility = { [weak self] in self?.onOpenAccessibility?() }
        settingsView.onToggleLogin = { [weak self] in self?.onToggleLogin?() }
        settingsView.onSetRecordingWindow = { [weak self] in self?.onSetRecordingWindow?($0) }
        settingsView.onSetFormatNumbers = { [weak self] in self?.onSetFormatNumbers?($0) }
        settingsView.onSetAppearance = { [weak self] in self?.onSetAppearance?($0) }

        for v in [homeView, historyView, settingsView] as [NSView] {
            content.addSubview(v)
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: content.topAnchor),
                v.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                v.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            ])
        }

        root.addSubview(sidebar)
        root.addSubview(content)

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 210),

            // Leave room at the top for the traffic-light buttons.
            topGroup.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 44),
            topGroup.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            topGroup.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),

            bottomGroup.topAnchor.constraint(equalTo: topGroup.bottomAnchor, constant: 16),
            bottomGroup.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            bottomGroup.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),

            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])

        window.contentView = root
        self.window = window

        // Push cached state into the freshly built views.
        homeView.updateStatus(state: statusState, text: statusText)
        homeView.updateShortcut(shortcut)
        settingsView.updateModel(model)
        settingsView.updateDevice(device)
        settingsView.updateShortcut(shortcut.displayString)
        settingsView.updateToggleShortcut(toggleShortcut)
        settingsView.updateRecordingWindow(recordingWindow)
        settingsView.updateFormatNumbers(formatNumbers)
        settingsView.updateAppearance(appearance)
        refreshLoginState()
    }

    private func makeSidebarItem(_ title: String, symbol: String, color: NSColor, section: Section) -> ClickableRow {
        let row = ClickableRow(action: { [weak self] in self?.select(section) })
        let tile = DesignKit.iconTile(symbol: symbol, color: color)
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(tile)
        row.addSubview(label)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 38),
            row.widthAnchor.constraint(greaterThanOrEqualToConstant: 186),
            tile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            tile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -8),
        ])
        sidebarItems.append((row, section))
        return row
    }

    private func select(_ section: Section) {
        homeView?.isHidden = section != .home
        historyView?.isHidden = section != .history
        settingsView?.isHidden = section != .settings
        if section == .history { historyView?.reload() }
        if section == .home { homeView?.reloadStats() }
        for item in sidebarItems { item.view.isSelected = (item.section == section) }
    }

    func windowWillClose(_ notification: Notification) {}
}
