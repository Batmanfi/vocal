import AppKit
import AVFoundation
import ApplicationServices
import Foundation
import ServiceManagement

enum AppState {
    case loading
    case idle
    case recording
    case transcribing
    case error

    var icon: String {
        switch self {
        case .loading: return "⏳"
        case .idle: return "🎙"
        case .recording: return "🔴"
        case .transcribing: return "⚙️"
        case .error: return "!"
        }
    }
}

struct VocalConfig: Codable {
    var model: String = "mlx-community/parakeet-tdt-0.6b-v2"
    var sampleRate: Double = 16_000
    var minSamples: Int = 8_000
    var pasteStrategy: String = "clipboard"
    var restoreClipboard: Bool = true
    var pythonExecutable: String? = nil

    // Push-to-talk trigger (see HotkeySpec). Defaults to Right Option for back-compat.
    var triggerKeyCode: Int = 61
    var triggerModifierFlags: UInt64 = 0
    var triggerIsModifierOnly: Bool = true

    // Toggle (continuous) trigger: press to start recording, press again to stop.
    // Defaults to Option+Space.
    var toggleEnabled: Bool = true
    var toggleKeyCode: Int = 49
    var toggleModifierFlags: UInt64 = CGEventFlags.maskAlternate.rawValue
    var toggleIsModifierOnly: Bool = false

    // Recording HUD style: "classic", "mini", or "none".
    var recordingWindow: String = "classic"
    // Convert spoken numbers to digits in the inserted text.
    var formatNumbers: Bool = true
    // Window appearance: "system", "light", or "dark".
    var appearance: String = "system"

    var hotkey: HotkeySpec {
        HotkeySpec(keyCode: triggerKeyCode, modifierFlags: triggerModifierFlags, isModifierOnly: triggerIsModifierOnly)
    }

    mutating func setHotkey(_ spec: HotkeySpec) {
        triggerKeyCode = spec.keyCode
        triggerModifierFlags = spec.modifierFlags
        triggerIsModifierOnly = spec.isModifierOnly
    }

    var toggleHotkey: HotkeySpec {
        HotkeySpec(keyCode: toggleKeyCode, modifierFlags: toggleModifierFlags, isModifierOnly: toggleIsModifierOnly)
    }

    mutating func setToggleHotkey(_ spec: HotkeySpec) {
        toggleKeyCode = spec.keyCode
        toggleModifierFlags = spec.modifierFlags
        toggleIsModifierOnly = spec.isModifierOnly
    }

    init() {}

    // Tolerant decoding: missing keys (e.g. an older config.json) fall back to defaults
    // instead of failing to load the whole config.
    init(from decoder: Decoder) throws {
        let defaults = VocalConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? defaults.model
        sampleRate = (try? c.decodeIfPresent(Double.self, forKey: .sampleRate)) ?? defaults.sampleRate
        minSamples = (try? c.decodeIfPresent(Int.self, forKey: .minSamples)) ?? defaults.minSamples
        pasteStrategy = (try? c.decodeIfPresent(String.self, forKey: .pasteStrategy)) ?? defaults.pasteStrategy
        restoreClipboard = (try? c.decodeIfPresent(Bool.self, forKey: .restoreClipboard)) ?? defaults.restoreClipboard
        pythonExecutable = (try? c.decodeIfPresent(String.self, forKey: .pythonExecutable)) ?? defaults.pythonExecutable
        triggerKeyCode = (try? c.decodeIfPresent(Int.self, forKey: .triggerKeyCode)) ?? defaults.triggerKeyCode
        triggerModifierFlags = (try? c.decodeIfPresent(UInt64.self, forKey: .triggerModifierFlags)) ?? defaults.triggerModifierFlags
        triggerIsModifierOnly = (try? c.decodeIfPresent(Bool.self, forKey: .triggerIsModifierOnly)) ?? defaults.triggerIsModifierOnly
        toggleEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .toggleEnabled)) ?? defaults.toggleEnabled
        toggleKeyCode = (try? c.decodeIfPresent(Int.self, forKey: .toggleKeyCode)) ?? defaults.toggleKeyCode
        toggleModifierFlags = (try? c.decodeIfPresent(UInt64.self, forKey: .toggleModifierFlags)) ?? defaults.toggleModifierFlags
        toggleIsModifierOnly = (try? c.decodeIfPresent(Bool.self, forKey: .toggleIsModifierOnly)) ?? defaults.toggleIsModifierOnly
        recordingWindow = (try? c.decodeIfPresent(String.self, forKey: .recordingWindow)) ?? defaults.recordingWindow
        formatNumbers = (try? c.decodeIfPresent(Bool.self, forKey: .formatNumbers)) ?? defaults.formatNumbers
        appearance = (try? c.decodeIfPresent(String.self, forKey: .appearance)) ?? defaults.appearance
    }

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/vocal/config.json")
    }

    static func load() throws -> VocalConfig {
        let url = configURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(VocalConfig.self, from: data)
        }

        let config = VocalConfig()
        config.save()
        return config
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        try? encoder.encode(self).write(to: VocalConfig.configURL, options: .atomic)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusPulseTimer: Timer?
    private var statusPulseStart = Date()
    private var statusMenuItem = NSMenuItem(title: "Loading model...", action: nil, keyEquivalent: "")
    private var lastEventMenuItem = NSMenuItem(title: "Last: Launching", action: nil, keyEquivalent: "")
    private var openWindowMenuItem = NSMenuItem(title: "Open Vocal Window", action: #selector(showMainWindow), keyEquivalent: "")
    private var historyMenuItem = NSMenuItem(title: "History…", action: #selector(showHistory), keyEquivalent: "")
    private var shortcutMenuItem = NSMenuItem(title: "Change Shortcut…", action: #selector(changeShortcut), keyEquivalent: "")
    private var loginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private var permissionsMenuItem = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openPrivacySettings), keyEquivalent: "")
    private var quitMenuItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")

    private let stateQueue = DispatchQueue(label: "local.vocal.app.state")
    private var isRecording = false
    private var isReady = false
    private var config = VocalConfig()
    private var recorder: AudioRecorder?
    private var hotkeyMonitor: HotkeyMonitor?
    private var toggleMonitor: HotkeyMonitor?
    private var transcriber: ParakeetBridge?
    private let mainWindow = MainWindowController()
    private var activeRecorder: HotkeyRecorderWindowController?
    private let recordingHUD = RecordingHUD()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        do {
            config = try VocalConfig.load()
        } catch {
            setState(.error, status: "Config failed: \(error.localizedDescription)")
        }

        applyAppearance(config.appearance)

        recorder = AudioRecorder(sampleRate: config.sampleRate)
        recorder?.onLevel = { [weak self] level in self?.recordingHUD.addLevel(level) }
        buildMainMenu()
        buildStatusItem()
        wireMainWindow()
        requestMicrophoneAccessIfNeeded()
        promptForAccessibilityIfNeeded()
        startTranscriber()
        mainWindow.show(section: .home)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow.show(section: .home)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the menu bar after the window is closed.
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyMonitor?.stop()
        toggleMonitor?.stop()
        recordingHUD.hide()
        transcriber?.stop()
    }

    private func wireMainWindow() {
        mainWindow.onChangeShortcut = { [weak self] in self?.changeShortcut() }
        mainWindow.onChangeToggleShortcut = { [weak self] in self?.changeToggleShortcut() }
        mainWindow.onOpenAccessibility = { [weak self] in self?.openPrivacySettings() }
        mainWindow.onToggleLogin = { [weak self] in self?.toggleLaunchAtLogin() }
        mainWindow.onSetRecordingWindow = { [weak self] in self?.setRecordingWindow($0) }
        mainWindow.onSetFormatNumbers = { [weak self] in self?.setFormatNumbers($0) }
        mainWindow.onSetAppearance = { [weak self] in self?.setAppearance($0) }
        mainWindow.loginEnabledProvider = { SMAppService.mainApp.status == .enabled }
        mainWindow.updateModel(config.model)
        mainWindow.updateShortcut(config.hotkey)
        mainWindow.updateToggleShortcut(config.toggleHotkey.displayString)
        mainWindow.updateRecordingWindow(config.recordingWindow)
        mainWindow.updateFormatNumbers(config.formatNumbers)
        mainWindow.updateAppearance(config.appearance)
        mainWindow.refreshLoginState()
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        applyStatusImage(for: .loading)

        let menu = NSMenu()
        statusMenuItem.isEnabled = false
        lastEventMenuItem.isEnabled = false
        openWindowMenuItem.target = self
        historyMenuItem.target = self
        shortcutMenuItem.target = self
        loginMenuItem.target = self
        permissionsMenuItem.target = self
        quitMenuItem.target = self
        updateShortcutMenuTitle()
        updateLoginMenuState()

        menu.addItem(statusMenuItem)
        menu.addItem(lastEventMenuItem)
        menu.addItem(.separator())
        menu.addItem(openWindowMenuItem)
        menu.addItem(historyMenuItem)
        menu.addItem(shortcutMenuItem)
        menu.addItem(loginMenuItem)
        menu.addItem(.separator())
        menu.addItem(permissionsMenuItem)
        menu.addItem(.separator())
        menu.addItem(quitMenuItem)
        statusItem.menu = menu
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Vocal", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let hide = NSMenuItem(title: "Hide Vocal", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hide)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Vocal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quit)
        appItem.submenu = appMenu

        // Edit menu so the search field supports cut/copy/paste/select-all shortcuts.
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func startTranscriber() {
        do {
            let bridge = try ParakeetBridge(config: config)
            transcriber = bridge
            bridge.start(
                onReady: { [weak self] device in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.mainWindow.updateDevice("Device: \(device)")
                        self.isReady = true
                        self.setState(.idle, status: self.readyStatus())
                        self.setLastEvent("Model loaded; arming hotkey")
                        self.startHotkeyMonitor()
                    }
                },
                onError: { [weak self] message in
                    DispatchQueue.main.async {
                        self?.setState(.error, status: message)
                    }
                },
                onProgress: { [weak self] pct, done, total in
                    DispatchQueue.main.async {
                        guard let self, !self.isReady else { return }
                        let f = ByteCountFormatter()
                        f.allowedUnits = [.useMB, .useGB]
                        f.countStyle = .file
                        let downloaded = f.string(fromByteCount: done)
                        let size = f.string(fromByteCount: total)
                        self.setState(.loading,
                                      status: "Downloading speech model… \(pct)% (\(downloaded) / \(size))")
                        self.setLastEvent("First run: downloading model (one time)")
                    }
                }
            )
        } catch {
            setState(.error, status: "Transcriber failed: \(error.localizedDescription)")
        }
    }

    private func startHotkeyMonitor() {
        hotkeyMonitor = HotkeyMonitor(
            spec: config.hotkey,
            onPress: { [weak self] in
                self?.setLastEvent("Shortcut pressed")
                self?.beginRecording()
            },
            onRelease: { [weak self] in
                self?.setLastEvent("Shortcut released")
                self?.finishRecording()
            },
            onFailure: { [weak self] message in
                DispatchQueue.main.async {
                    self?.setState(.error, status: message)
                }
            }
        )
        hotkeyMonitor?.start()

        if config.toggleEnabled {
            toggleMonitor = HotkeyMonitor(
                spec: config.toggleHotkey,
                onPress: { [weak self] in self?.toggleRecording() },
                onRelease: {},
                onFailure: { _ in }
            )
            toggleMonitor?.start()
        }
        setLastEvent("Hotkey listener armed")
    }

    /// Continuous mode: first press starts recording (HUD appears), second press stops
    /// and transcribes/pastes.
    private func toggleRecording() {
        stateQueue.async {
            if self.isRecording {
                DispatchQueue.main.async { self.finishRecording() }
            } else {
                DispatchQueue.main.async { self.beginRecording() }
            }
        }
    }

    private func hudStyle() -> RecordingHUD.Style {
        RecordingHUD.Style(rawValue: config.recordingWindow) ?? .classic
    }

    private func beginRecording() {
        stateQueue.async {
            guard self.isReady, !self.isRecording else { return }
            self.isRecording = true
            DispatchQueue.main.async {
                self.setState(.recording, status: "Recording...")
                self.setLastEvent("Recording started")
                self.recordingHUD.show(style: self.hudStyle())
            }

            do {
                try self.recorder?.start()
            } catch {
                self.isRecording = false
                DispatchQueue.main.async {
                    self.setState(.error, status: "Recording failed: \(error.localizedDescription)")
                    self.setLastEvent("Recording failed")
                }
            }
        }
    }

    private func finishRecording() {
        stateQueue.async {
            guard self.isRecording else { return }
            self.isRecording = false
            DispatchQueue.main.async { self.recordingHUD.hide() }

            do {
                guard let audioURL = try self.recorder?.stop() else {
                    DispatchQueue.main.async {
                        self.setState(.idle, status: self.readyStatus())
                        self.setLastEvent("Stop ignored; no audio")
                    }
                    return
                }

                let duration = self.recorder?.lastRecordedDuration ?? 0
                let targetRateSampleCount = Int(duration * self.config.sampleRate)
                guard targetRateSampleCount >= self.config.minSamples else {
                    try? FileManager.default.removeItem(at: audioURL)
                    DispatchQueue.main.async {
                        self.setState(.idle, status: self.readyStatus())
                        self.setLastEvent(String(format: "Ignored short tap %.2fs", duration))
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.setState(.transcribing, status: "Transcribing...")
                    self.setLastEvent(String(format: "Recorded %.2fs; transcribing", duration))
                }
                self.transcribeAndPaste(audioURL: audioURL)
            } catch {
                DispatchQueue.main.async {
                    self.setState(.error, status: "Stop failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func transcribeAndPaste(audioURL: URL) {
        transcriber?.transcribe(audioURL: audioURL) { [weak self] result in
            try? FileManager.default.removeItem(at: audioURL)
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let rawText):
                    let text = self.config.formatNumbers ? NumberWordConverter.convert(rawText) : rawText
                    if text.isEmpty {
                        self.setState(.idle, status: "No speech detected.")
                        self.setLastEvent("Transcription returned empty text")
                    } else {
                        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
                        HistoryStore.shared.add(text: text, appName: appName)

                        let outcome = PasteService.paste(
                            text,
                            strategy: self.config.pasteStrategy,
                            restoreClipboard: self.config.restoreClipboard
                        )
                        switch outcome {
                        case .pasted:
                            self.setState(.idle, status: "Inserted transcription.")
                            self.setLastEvent("Pasted \(text.count) characters")
                        case .copiedToClipboardOnly:
                            self.handleAccessibilityBlocked(characterCount: text.count)
                        case .failed:
                            self.setState(.error, status: "Could not insert transcription.")
                            self.setLastEvent("Paste failed")
                        }
                    }
                case .failure(let error):
                    self.setState(.error, status: "Transcription failed: \(error.localizedDescription)")
                    self.setLastEvent("Transcription failed")
                }
            }
        }
    }

    private func readyStatus() -> String {
        "Ready. Hold \(config.hotkey.displayString) to dictate."
    }

    private func setState(_ state: AppState, status: String) {
        applyStatusImage(for: state)
        statusMenuItem.title = status
        mainWindow.updateStatus(state: state, text: status)
        NSLog("Vocal state: \(status)")
    }

    /// Render the Vocal glyph (per state) into the menu-bar button, falling back to
    /// the emoji if the glyph asset can't be loaded. Pulses while recording/transcribing.
    private func applyStatusImage(for state: AppState) {
        guard let button = statusItem?.button else { return }
        if let image = MenuBarIcon.image(for: state) {
            button.image = image
            button.title = ""
            button.imagePosition = .imageOnly
        } else {
            button.image = nil
            button.title = state.icon
        }
        if state == .recording || state == .transcribing {
            startStatusPulse()
        } else {
            stopStatusPulse()
        }
    }

    private func startStatusPulse() {
        guard statusPulseTimer == nil else { return }
        statusPulseStart = Date()
        statusPulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, let button = self.statusItem?.button else { return }
            // Smooth cosine pulse, ~1.4s period, alpha between 0.4 and 1.0.
            let t = Date().timeIntervalSince(self.statusPulseStart)
            button.alphaValue = 0.7 + 0.3 * cos(t * .pi * 2 / 1.4)
        }
    }

    private func stopStatusPulse() {
        statusPulseTimer?.invalidate()
        statusPulseTimer = nil
        statusItem?.button?.alphaValue = 1.0
    }

    private func setLastEvent(_ message: String) {
        lastEventMenuItem.title = "Last: \(message)"
        mainWindow.updateLastEvent(message)
        NSLog("Vocal last event: \(message)")
    }

    private func requestMicrophoneAccessIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        default:
            break
        }
    }

    private func promptForAccessibilityIfNeeded() {
        AccessibilityService.shared.registerWithSystemPrompt()
    }

    private func handleAccessibilityBlocked(characterCount: Int) {
        setState(.error, status: "Copied to clipboard — press ⌘V. Grant Accessibility to auto-paste.")
        setLastEvent("Accessibility missing; \(characterCount) chars left on clipboard")
        AccessibilityService.shared.showBlockedInstructions(bundlePath: Bundle.main.bundleURL.path)
        AccessibilityService.shared.startPolling { [weak self] in
            guard let self else { return }
            self.setState(.idle, status: self.readyStatus())
            self.setLastEvent("Accessibility granted")
        }
    }

    // MARK: - Menu actions

    @objc private func showMainWindow() {
        mainWindow.show(section: .home)
    }

    @objc private func showHistory() {
        mainWindow.show(section: .history)
    }

    @objc private func changeShortcut() {
        presentRecorder(current: config.hotkey) { [weak self] spec in
            guard let self else { return }
            self.config.setHotkey(spec)
            self.config.save()
            self.hotkeyMonitor?.update(spec: spec)
            self.updateShortcutMenuTitle()
            self.mainWindow.updateShortcut(spec)
            self.setState(.idle, status: self.readyStatus())
            self.setLastEvent("Hold shortcut set to \(spec.displayString)")
        }
    }

    private func changeToggleShortcut() {
        presentRecorder(current: config.toggleHotkey) { [weak self] spec in
            guard let self else { return }
            self.config.setToggleHotkey(spec)
            self.config.save()
            self.toggleMonitor?.update(spec: spec)
            self.mainWindow.updateToggleShortcut(spec.displayString)
            self.setLastEvent("Toggle shortcut set to \(spec.displayString)")
        }
    }

    /// Shows the key recorder, pausing both monitors so the current shortcut doesn't fire
    /// while the user is choosing a new one.
    private func presentRecorder(current: HotkeySpec, onSaved: @escaping (HotkeySpec) -> Void) {
        hotkeyMonitor?.setEnabled(false)
        toggleMonitor?.setEnabled(false)
        activeRecorder = HotkeyRecorderWindowController(
            onSave: { spec in onSaved(spec) },
            onClose: { [weak self] in
                self?.hotkeyMonitor?.setEnabled(true)
                self?.toggleMonitor?.setEnabled(true)
            }
        )
        activeRecorder?.show(current: current)
    }

    private func setRecordingWindow(_ style: String) {
        config.recordingWindow = style
        config.save()
        mainWindow.updateRecordingWindow(style)
        setLastEvent("Recording window: \(style)")
    }

    private func setFormatNumbers(_ enabled: Bool) {
        config.formatNumbers = enabled
        config.save()
        mainWindow.updateFormatNumbers(enabled)
    }

    private func setAppearance(_ mode: String) {
        config.appearance = mode
        config.save()
        applyAppearance(mode)
        mainWindow.updateAppearance(mode)
        setLastEvent("Appearance: \(mode)")
    }

    /// Apply "system" / "light" / "dark" to the whole app. Setting `NSApp.appearance`
    /// makes every window (and the views in them) follow; the menu-bar glyph is rendered
    /// by the system status bar and is unaffected.
    private func applyAppearance(_ mode: String) {
        switch mode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil // follow the system setting
        }
    }

    private func updateShortcutMenuTitle() {
        shortcutMenuItem.title = "Shortcut: \(config.hotkey.displayString) — Change…"
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                setLastEvent("Disabled launch at login")
            } else {
                try SMAppService.mainApp.register()
                setLastEvent("Enabled launch at login")
            }
        } catch {
            setLastEvent("Login item error: \(error.localizedDescription)")
        }
        updateLoginMenuState()
        mainWindow.refreshLoginState()
    }

    private func updateLoginMenuState() {
        loginMenuItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc private func openPrivacySettings() {
        AccessibilityService.shared.openAccessibilitySettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
