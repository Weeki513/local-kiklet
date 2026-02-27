import AppKit
import Foundation

struct HotkeyModifiers: Codable, Hashable {
    var command: Bool
    var option: Bool
    var shift: Bool
    var control: Bool

    init(command: Bool = false, option: Bool = false, shift: Bool = false, control: Bool = false) {
        self.command = command
        self.option = option
        self.shift = shift
        self.control = control
    }

    static var none: HotkeyModifiers { HotkeyModifiers() }

    var isEmpty: Bool {
        !command && !option && !shift && !control
    }

    var count: Int {
        [command, option, shift, control].filter { $0 }.count
    }

    var eventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if option { flags.insert(.maskAlternate) }
        if shift { flags.insert(.maskShift) }
        if control { flags.insert(.maskControl) }
        return flags
    }

    var nsFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if option { flags.insert(.option) }
        if shift { flags.insert(.shift) }
        if control { flags.insert(.control) }
        return flags
    }

    static func from(_ flags: CGEventFlags) -> HotkeyModifiers {
        HotkeyModifiers(
            command: flags.contains(.maskCommand),
            option: flags.contains(.maskAlternate),
            shift: flags.contains(.maskShift),
            control: flags.contains(.maskControl)
        )
    }

    static func from(_ flags: NSEvent.ModifierFlags) -> HotkeyModifiers {
        HotkeyModifiers(
            command: flags.contains(.command),
            option: flags.contains(.option),
            shift: flags.contains(.shift),
            control: flags.contains(.control)
        )
    }

    var symbols: String {
        var text = ""
        if control { text += "⌃" }
        if option { text += "⌥" }
        if shift { text += "⇧" }
        if command { text += "⌘" }
        return text
    }
}

struct Hotkey: Codable, Hashable {
    var keyCode: Int?
    var modifiers: HotkeyModifiers

    init(keyCode: Int?, modifiers: HotkeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    static var defaultHold: Hotkey {
        Hotkey(keyCode: nil, modifiers: HotkeyModifiers(option: true))
    }

    static var defaultToggle: Hotkey {
        Hotkey(keyCode: 49, modifiers: HotkeyModifiers(command: true, option: true))
    }

    var isModifierOnly: Bool {
        guard !modifiers.isEmpty else { return false }
        guard let keyCode else { return true }
        return Self.isModifierKeyCode(keyCode)
    }

    var displayString: String {
        if let keyCode {
            if Self.isModifierKeyCode(keyCode) {
                return Self.modifierOnlyDisplayName(for: keyCode, modifiers: modifiers)
            }
            let keyName = Self.displayName(for: keyCode)
            return "\(modifiers.symbols)\(keyName)"
        }
        if modifiers.isEmpty {
            return "Не задано"
        }
        return modifiers.symbols
    }

    func matches(keyCode incomingKeyCode: Int?, flags: CGEventFlags) -> Bool {
        let incomingModifiers = HotkeyModifiers.from(flags)
        guard incomingModifiers == modifiers else { return false }
        return keyCode == incomingKeyCode
    }

    static func isModifierKeyCode(_ keyCode: Int) -> Bool {
        modifierSideByKeyCode[keyCode] != nil
    }

    static func displayName(for keyCode: Int) -> String {
        switch keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            if let scalar = keyCodeToScalar[keyCode] {
                return scalar.uppercased()
            }
            return "Key(\(keyCode))"
        }
    }

    private static func modifierOnlyDisplayName(for keyCode: Int, modifiers: HotkeyModifiers) -> String {
        guard let side = modifierSideByKeyCode[keyCode] else {
            return modifiers.symbols
        }
        return "\(modifiers.symbols) \(side)"
    }

    private static let keyCodeToScalar: [Int: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2", 20: "3",
        21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]",
        31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l", 38: "j", 39: "'", 40: "k", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "n", 46: "m", 47: ".", 50: "`"
    ]

    private static let modifierSideByKeyCode: [Int: String] = [
        54: "Right Cmd",
        55: "Left Cmd",
        56: "Left Shift",
        58: "Left Option",
        59: "Left Ctrl",
        60: "Right Shift",
        61: "Right Option",
        62: "Right Ctrl"
    ]
}
