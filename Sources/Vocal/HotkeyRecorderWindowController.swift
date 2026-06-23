import AppKit

/// A small window that captures the next key combination the user presses.
/// - Pressing a regular key with at least one modifier records a combo (⌥Space, ⌃⌘D…).
/// - Pressing and releasing a single modifier alone records a modifier-only trigger
///   (Right ⌥, fn…), which is the recommended push-to-talk style.
final class HotkeyRecorderWindowController: NSObject {
    private var window: NSWindow?
    private var monitor: Any?
    private var captureLabel: NSTextField!
    private var hintLabel: NSTextField!
    private var saveButton: NSButton!

    private var captured: HotkeySpec?
    private var pendingModifierKeyCode: Int?
    private let onSave: (HotkeySpec) -> Void
    private let onClose: () -> Void

    init(onSave: @escaping (HotkeySpec) -> Void, onClose: @escaping () -> Void) {
        self.onSave = onSave
        self.onClose = onClose
    }

    func show(current: HotkeySpec) {
        captured = nil
        pendingModifierKeyCode = nil
        if window == nil { buildWindow() }
        captureLabel.stringValue = current.displayString
        hintLabel.stringValue = "Current shortcut. Press a new one to change it."
        saveButton.isEnabled = false
        startCapturing()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Shortcut"
        window.isReleasedWhenClosed = false
        window.delegate = WindowCloseProxy.shared
        WindowCloseProxy.shared.onWillClose = { [weak self] in self?.stopCapturing(); self?.onClose() }

        let content = NSView()

        let prompt = NSTextField(labelWithString: "Hold this key (or combo) to dictate:")
        prompt.font = .systemFont(ofSize: 13)
        prompt.translatesAutoresizingMaskIntoConstraints = false

        captureLabel = NSTextField(labelWithString: "")
        captureLabel.alignment = .center
        captureLabel.font = .systemFont(ofSize: 30, weight: .semibold)
        captureLabel.translatesAutoresizingMaskIntoConstraints = false

        hintLabel = NSTextField(wrappingLabelWithString: "")
        hintLabel.alignment = .center
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(prompt)
        content.addSubview(captureLabel)
        content.addSubview(hintLabel)
        content.addSubview(saveButton)
        content.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            prompt.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            prompt.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            captureLabel.topAnchor.constraint(equalTo: prompt.bottomAnchor, constant: 18),
            captureLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            captureLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            hintLabel.topAnchor.constraint(equalTo: captureLabel.bottomAnchor, constant: 14),
            hintLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            hintLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            saveButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            saveButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            cancelButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
        ])

        window.contentView = content
        self.window = window
    }

    // MARK: - Capture

    private func startCapturing() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
    }

    private func stopCapturing() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Returns true if the event was consumed by the recorder.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            let mods = cgFlags(from: event.modifierFlags)
            guard !mods.isEmpty else {
                hintLabel.stringValue = "Add a modifier (⌘ ⌥ ⌃ ⇧) — or press a single modifier key alone."
                return true
            }
            let spec = HotkeySpec(keyCode: Int(event.keyCode), modifierFlags: mods.rawValue, isModifierOnly: false)
            setCaptured(spec)
            pendingModifierKeyCode = nil
            return true
        case .flagsChanged:
            let code = Int(event.keyCode)
            let activeMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if !activeMods.isEmpty {
                // A modifier went down — remember it as a candidate single-modifier trigger.
                pendingModifierKeyCode = code
            } else {
                // All modifiers released with no regular key pressed → single-modifier trigger.
                if let pending = pendingModifierKeyCode,
                   HotkeySpec.maskForModifier(keyCode: pending) != nil {
                    setCaptured(HotkeySpec(keyCode: pending, modifierFlags: 0, isModifierOnly: true))
                }
                pendingModifierKeyCode = nil
            }
            return false // don't swallow modifier changes
        default:
            return false
        }
    }

    private func setCaptured(_ spec: HotkeySpec) {
        captured = spec
        captureLabel.stringValue = spec.displayString
        hintLabel.stringValue = "Press Save to use this shortcut."
        saveButton.isEnabled = true
    }

    private func cgFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var cg: CGEventFlags = []
        if flags.contains(.command) { cg.insert(.maskCommand) }
        if flags.contains(.option) { cg.insert(.maskAlternate) }
        if flags.contains(.control) { cg.insert(.maskControl) }
        if flags.contains(.shift) { cg.insert(.maskShift) }
        if flags.contains(.function) { cg.insert(.maskSecondaryFn) }
        return cg
    }

    // MARK: - Buttons

    @objc private func save() {
        guard let captured else { return }
        stopCapturing()
        onSave(captured)
        window?.close()
    }

    @objc private func cancel() {
        stopCapturing()
        window?.close()
    }
}

/// Bridges NSWindowDelegate's willClose back to the recorder so capturing is torn down
/// even when the user clicks the red close button.
private final class WindowCloseProxy: NSObject, NSWindowDelegate {
    static let shared = WindowCloseProxy()
    var onWillClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onWillClose?() }
}
