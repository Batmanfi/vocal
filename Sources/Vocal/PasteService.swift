import AppKit
import Foundation

enum PasteOutcome {
    /// Accessibility is granted and Cmd+V (or synthetic typing) was injected.
    case pasted
    /// Accessibility is missing. Text was left on the clipboard so the user can press Cmd+V manually.
    case copiedToClipboardOnly
    /// Nothing usable happened (empty text was a no-op success, so this is a real failure path only).
    case failed
}

enum PasteService {
    @discardableResult
    static func paste(_ text: String, strategy: String, restoreClipboard: Bool) -> PasteOutcome {
        guard !text.isEmpty else { return .pasted }

        // Fallback: even without Accessibility we can still put the text on the clipboard
        // so the transcription is never lost — the user just presses Cmd+V themselves.
        guard AXIsProcessTrusted() else {
            NSLog("Vocal paste blocked: Accessibility not granted; leaving text on clipboard for manual paste")
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .copiedToClipboardOnly
        }

        if strategy == "type" {
            typeText(text)
            return .pasted
        }

        let pasteboard = NSPasteboard.general
        // Snapshot the current clipboard into fresh items. NSPasteboardItem does NOT
        // conform to NSCopying, so calling .copy() on it crashes (doesNotRecognizeSelector
        // copyWithZone:). Instead, copy each type's raw data into newly allocated items —
        // a pasteboard item can only be written once, so we never reuse the originals.
        let existingItems: [NSPasteboardItem]? = restoreClipboard
            ? pasteboard.pasteboardItems?.compactMap { item in
                let snapshot = NSPasteboardItem()
                var hasData = false
                for type in item.types {
                    if let data = item.data(forType: type) {
                        snapshot.setData(data, forType: type)
                        hasData = true
                    }
                }
                return hasData ? snapshot : nil
            }
            : nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        sendCommandV()

        if restoreClipboard, let existingItems, !existingItems.isEmpty {
            // Give the target app time to read the pasteboard before we restore the prior contents.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                pasteboard.clearContents()
                pasteboard.writeObjects(existingItems)
            }
        }
        return .pasted
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func typeText(_ text: String) {
        for scalar in text.unicodeScalars {
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                continue
            }
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: [UniChar(scalar.value)])
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: [UniChar(scalar.value)])
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
