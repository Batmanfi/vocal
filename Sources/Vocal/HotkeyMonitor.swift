import AppKit
import ApplicationServices
import Foundation

/// Describes the push-to-talk trigger.
/// - A *modifier-only* trigger (e.g. Right Option) is matched on `.flagsChanged`
///   by the modifier's key code; the event is never swallowed.
/// - A *combo* trigger (modifiers + a regular key, e.g. ⌥Space) is matched on
///   `.keyDown`/`.keyUp` and swallowed so the keystroke does not reach the app.
struct HotkeySpec: Codable, Equatable {
    var keyCode: Int          // modifier-only: the modifier's key code; combo: the regular key's key code
    var modifierFlags: UInt64 // combo: required device-independent CGEventFlags; modifier-only: 0
    var isModifierOnly: Bool

    static let rightOption = HotkeySpec(keyCode: 61, modifierFlags: 0, isModifierOnly: true)

    /// Modifier bits we care about (ignores caps lock, numeric pad, etc.).
    static let relevantMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn]

    var displayString: String {
        if isModifierOnly {
            return HotkeySpec.modifierName(forKeyCode: keyCode) ?? "Key \(keyCode)"
        }
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: modifierFlags)
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        if flags.contains(.maskSecondaryFn) { parts.append("fn") }
        parts.append(HotkeySpec.keyName(forKeyCode: keyCode))
        return parts.joined()
    }

    static func modifierName(forKeyCode code: Int) -> String? {
        switch code {
        case 54: return "Right ⌘"
        case 55: return "Left ⌘"
        case 56: return "Left ⇧"
        case 60: return "Right ⇧"
        case 58: return "Left ⌥"
        case 61: return "Right ⌥"
        case 59: return "Left ⌃"
        case 62: return "Right ⌃"
        case 63: return "fn"
        default: return nil
        }
    }

    static func maskForModifier(keyCode code: Int) -> CGEventFlags? {
        switch code {
        case 54, 55: return .maskCommand
        case 56, 60: return .maskShift
        case 58, 61: return .maskAlternate
        case 59, 62: return .maskControl
        case 63: return .maskSecondaryFn
        default: return nil
        }
    }

    static func keyName(forKeyCode code: Int) -> String {
        let map: [Int: String] = [
            49: "Space", 36: "Return", 48: "Tab", 53: "Esc", 51: "Delete", 76: "Enter",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
            34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        ]
        return map[code] ?? "Key \(code)"
    }
}

final class HotkeyMonitor {
    private var spec: HotkeySpec
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private let onFailure: (String) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false

    init(spec: HotkeySpec,
         onPress: @escaping () -> Void,
         onRelease: @escaping () -> Void,
         onFailure: @escaping (String) -> Void) {
        self.spec = spec
        self.onPress = onPress
        self.onRelease = onRelease
        self.onFailure = onFailure
    }

    /// Swap in a new trigger without rebuilding the tap.
    func update(spec newSpec: HotkeySpec) {
        spec = newSpec
        if isPressed {
            isPressed = false
            onRelease()
        }
    }

    /// Temporarily ignore events (used while recording a new shortcut).
    func setEnabled(_ enabled: Bool) {
        guard let eventTap else { return }
        if !enabled && isPressed {
            isPressed = false
            onRelease()
        }
        CGEvent.tapEnable(tap: eventTap, enable: enabled)
    }

    func start() {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            NSLog("Vocal hotkey tap failed: Input Monitoring permission is likely missing")
            onFailure("Input Monitoring permission is required for the shortcut.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("Vocal hotkey tap armed for \(spec.displayString)")
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        runLoopSource = nil
        eventTap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system can silently disable a tap; re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if spec.isModifierOnly {
            guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            guard keyCode == spec.keyCode, let mask = HotkeySpec.maskForModifier(keyCode: spec.keyCode) else {
                return Unmanaged.passUnretained(event)
            }
            setPressed(event.flags.contains(mask))
            return Unmanaged.passUnretained(event) // never swallow modifier keys
        }

        // Combo trigger: match key code + required modifiers, and swallow the keystroke.
        switch type {
        case .keyDown:
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == spec.keyCode && modifiersMatch(event.flags) {
                if !isPressed { setPressed(true) }
                return nil // swallow so the key is not typed into the focused app
            }
        case .keyUp:
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == spec.keyCode {
                if isPressed { setPressed(false) }
                return nil
            }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func modifiersMatch(_ flags: CGEventFlags) -> Bool {
        let required = CGEventFlags(rawValue: spec.modifierFlags).intersection(HotkeySpec.relevantMask)
        return flags.intersection(HotkeySpec.relevantMask) == required
    }

    private func setPressed(_ pressed: Bool) {
        if pressed && !isPressed {
            isPressed = true
            onPress()
        } else if !pressed && isPressed {
            isPressed = false
            onRelease()
        }
    }
}
