import AppKit
import ApplicationServices
import Foundation

/// Centralizes Accessibility (AXIsProcessTrusted) prompting, user-facing guidance,
/// and live detection of the permission being granted while the app keeps running.
final class AccessibilityService {
    static let shared = AccessibilityService()

    private let appName = "Vocal"
    private var pollTimer: Timer?
    private var lastAlertShown: Date?
    private var onGranted: (() -> Void)?

    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Registers the app with the system Accessibility list and shows the one-time
    /// system prompt if access has never been determined. Safe to call repeatedly.
    @discardableResult
    func registerWithSystemPrompt() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        // Deep-link straight to the Accessibility pane rather than the generic Privacy root.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Shows a clear, step-by-step alert with a button that jumps to the Accessibility pane.
    /// Throttled so a burst of blocked pastes does not stack dialogs.
    func showBlockedInstructions(bundlePath: String?) {
        if let last = lastAlertShown, Date().timeIntervalSince(last) < 30 { return }
        lastAlertShown = Date()

        let addLine: String
        if let bundlePath {
            addLine = "If \(appName) is not listed, click + and add:\n\(bundlePath)"
        } else {
            addLine = "If \(appName) is not listed, click + and add \(appName).app."
        }

        let alert = NSAlert()
        alert.messageText = "Allow \(appName) to paste"
        alert.informativeText = """
        \(appName) needs Accessibility access to insert text at your cursor.

        1. Click “Open Accessibility Settings”.
        2. Turn \(appName) on. \(addLine)
        3. If it was already on, toggle it off and back on — rebuilding the app can require re-approval.

        Your transcription is already on the clipboard, so you can press ⌘V to paste it right now.
        """
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    /// Polls until Accessibility is granted, then invokes `onGranted` once on the main queue.
    func startPolling(onGranted: @escaping () -> Void) {
        self.onGranted = onGranted
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if AXIsProcessTrusted() {
                timer.invalidate()
                self.pollTimer = nil
                let callback = self.onGranted
                self.onGranted = nil
                callback?()
            }
        }
    }
}
