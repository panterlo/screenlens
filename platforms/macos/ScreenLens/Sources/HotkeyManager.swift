import AppKit
import Carbon.HIToolbox

/// Manages global hotkeys via CGEvent tap.
class HotkeyManager {
    static let shared = HotkeyManager()

    struct Hotkey {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    struct Actions {
        var captureFullscreen: () -> Void = {}
        var captureRegion: () -> Void = {}
        var captureWindow: () -> Void = {}
        var openGallery: () -> Void = {}
    }

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    fileprivate var registeredShortcuts: [(Hotkey, () -> Void)] = []

    private init() {}

    // MARK: - Key Name → CGKeyCode Mapping

    private static let keyCodeMap: [String: CGKeyCode] = [
        "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03,
        "H": 0x04, "G": 0x05, "Z": 0x06, "X": 0x07,
        "C": 0x08, "V": 0x09, "B": 0x0B, "Q": 0x0C,
        "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10,
        "T": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
        "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19,
        "7": 0x1A, "8": 0x1C, "0": 0x1D, "O": 0x1F,
        "U": 0x20, "I": 0x22, "P": 0x23, "L": 0x25,
        "J": 0x26, "K": 0x28, "N": 0x2D, "M": 0x2E,
        "Space": 0x31, "Escape": 0x35, "Tab": 0x30,
        "Delete": 0x33, "Return": 0x24,
        "F1": 0x7A, "F2": 0x78, "F3": 0x63, "F4": 0x76,
        "F5": 0x60, "F6": 0x61, "F7": 0x62, "F8": 0x64,
        "F9": 0x65, "F10": 0x6D, "F11": 0x67, "F12": 0x6F,
    ]

    /// Reverse map: CGKeyCode → display name.
    static let keyNameMap: [CGKeyCode: String] = {
        var map: [CGKeyCode: String] = [:]
        for (name, code) in keyCodeMap { map[code] = name }
        return map
    }()

    // MARK: - Parse Hotkey String

    /// Parse a hotkey string like "Ctrl+Shift+F" into a Hotkey.
    static func parse(_ string: String) -> Hotkey? {
        let parts = string.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return nil }

        var flags: CGEventFlags = []
        var keyName: String?

        for part in parts {
            switch part.lowercased() {
            case "ctrl", "control": flags.insert(.maskControl)
            case "shift": flags.insert(.maskShift)
            case "alt", "option", "opt": flags.insert(.maskAlternate)
            case "cmd", "command": flags.insert(.maskCommand)
            default: keyName = part.uppercased()
            }
        }

        guard let name = keyName, let code = keyCodeMap[name] else { return nil }
        return Hotkey(keyCode: code, flags: flags)
    }

    /// Convert a Hotkey back to a display string like "Ctrl+Shift+F".
    static func displayString(for hotkey: Hotkey) -> String {
        var parts: [String] = []
        if hotkey.flags.contains(.maskControl) { parts.append("Ctrl") }
        if hotkey.flags.contains(.maskShift) { parts.append("Shift") }
        if hotkey.flags.contains(.maskAlternate) { parts.append("Alt") }
        if hotkey.flags.contains(.maskCommand) { parts.append("Cmd") }
        if let name = keyNameMap[hotkey.keyCode] {
            parts.append(name)
        }
        return parts.joined(separator: "+")
    }

    /// Convert modifier flags and a keyCode from an NSEvent to a display string.
    static func displayString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.option) { parts.append("Alt") }
        if modifiers.contains(.command) { parts.append("Cmd") }
        if let name = keyNameMap[keyCode] {
            parts.append(name)
        }
        return parts.joined(separator: "+")
    }

    // MARK: - Register / Unregister

    func register(shortcuts: AppConfig.HotkeyConfig, actions: Actions) {
        unregister()

        registeredShortcuts = []
        let pairs: [(String, () -> Void)] = [
            (shortcuts.captureFullscreen, actions.captureFullscreen),
            (shortcuts.captureRegion, actions.captureRegion),
            (shortcuts.captureWindow, actions.captureWindow),
            (shortcuts.openGallery, actions.openGallery),
        ]
        for (str, action) in pairs {
            if let hotkey = Self.parse(str) {
                registeredShortcuts.append((hotkey, action))
            }
        }

        guard !registeredShortcuts.isEmpty else { return }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyEventCallback,
            userInfo: refcon
        ) else {
            NSLog("HotkeyManager: failed to create event tap — check Accessibility permissions")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("HotkeyManager: registered \(registeredShortcuts.count) global hotkeys")
    }

    func unregister() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        registeredShortcuts = []
    }

    // MARK: - Event Tap Callback

    fileprivate func handleEvent(_ event: CGEvent) -> Bool {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let eventFlags = event.flags

        // Mask to only the modifier bits we care about
        let relevantMask: CGEventFlags = [.maskControl, .maskShift, .maskAlternate, .maskCommand]
        let maskedFlags = eventFlags.intersection(relevantMask)

        for (hotkey, action) in registeredShortcuts {
            if keyCode == hotkey.keyCode && maskedFlags == hotkey.flags {
                DispatchQueue.main.async { action() }
                return true // consume the event
            }
        }
        return false
    }
}

private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // If the tap is disabled by the system (e.g. timeout), re-enable it
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let refcon = refcon {
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passRetained(event)
    }

    guard type == .keyDown, let refcon = refcon else {
        return Unmanaged.passRetained(event)
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
    if manager.handleEvent(event) {
        return nil // consume the event
    }
    return Unmanaged.passRetained(event)
}
