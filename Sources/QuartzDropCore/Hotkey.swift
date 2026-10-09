import Foundation

/// Carbon modifier masks (`cmdKey`, `shiftKey`, `optionKey`, `controlKey`), kept here so the core
/// target does not have to import Carbon.
public struct HotkeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let command = HotkeyModifiers(rawValue: 0x0100)
    public static let shift = HotkeyModifiers(rawValue: 0x0200)
    public static let option = HotkeyModifiers(rawValue: 0x0800)
    public static let control = HotkeyModifiers(rawValue: 0x1000)
}

/// A global shortcut such as `cmd+alt+f`.
///
/// Key codes are macOS virtual key codes (`kVK_*`). Letter and punctuation codes follow the
/// physical ANSI key position, so non-QWERTY layouts bind by position, not by printed letter.
public struct Hotkey: Sendable, Hashable {
    public let raw: String
    public let modifiers: HotkeyModifiers
    public let keyCode: UInt32
    public let keyName: String

    /// Human-readable form using the macOS modifier glyphs, e.g. `⌃⌥⌘F`.
    public var display: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + keyName
    }

    /// The key token when `raw` ends in F21-F24, which plasma-drop accepts but macOS has no key
    /// codes for.
    public static func unsupportedKey(in raw: String) -> String? {
        guard let last = raw.split(separator: "+", omittingEmptySubsequences: false).last else {
            return nil
        }
        let key = last.trimmingCharacters(in: .whitespaces).lowercased()
        return ["f21", "f22", "f23", "f24"].contains(key) ? key : nil
    }

    public static func parse(_ input: String) throws -> Hotkey {
        let raw = input.trimmingCharacters(in: .whitespaces)
        let tokens = raw.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let keyToken = tokens.last else {
            throw ConfigError("hotkey must not be empty")
        }

        var modifiers: HotkeyModifiers = []
        for token in tokens.dropLast() {
            let modifier: HotkeyModifiers
            switch token.lowercased() {
            case "ctrl", "control": modifier = .control
            case "shift": modifier = .shift
            case "alt", "option", "opt": modifier = .option
            case "cmd", "command", "super", "meta", "win": modifier = .command
            default:
                throw ConfigError("unknown hotkey modifier '\(token.lowercased())' in '\(raw)'")
            }
            if modifiers.contains(modifier) {
                throw ConfigError("duplicate hotkey modifier '\(token)' in '\(raw)'")
            }
            modifiers.insert(modifier)
        }

        guard let (keyCode, keyName) = keyTable[keyToken.lowercased()] else {
            throw ConfigError("unknown hotkey key '\(keyToken)' in '\(raw)'")
        }

        return Hotkey(raw: raw, modifiers: modifiers, keyCode: keyCode, keyName: keyName)
    }
}

private let keyTable: [String: (UInt32, String)] = {
    var table: [String: (UInt32, String)] = [:]
    let letters: [(String, UInt32)] = [
        ("a", 0x00), ("s", 0x01), ("d", 0x02), ("f", 0x03), ("h", 0x04), ("g", 0x05),
        ("z", 0x06), ("x", 0x07), ("c", 0x08), ("v", 0x09), ("b", 0x0B), ("q", 0x0C),
        ("w", 0x0D), ("e", 0x0E), ("r", 0x0F), ("y", 0x10), ("t", 0x11), ("o", 0x1F),
        ("u", 0x20), ("i", 0x22), ("p", 0x23), ("l", 0x25), ("j", 0x26), ("k", 0x28),
        ("n", 0x2D), ("m", 0x2E),
    ]
    for (letter, code) in letters {
        table[letter] = (code, letter.uppercased())
    }

    let digits: [(String, UInt32)] = [
        ("1", 0x12), ("2", 0x13), ("3", 0x14), ("4", 0x15), ("5", 0x17),
        ("6", 0x16), ("7", 0x1A), ("8", 0x1C), ("9", 0x19), ("0", 0x1D),
    ]
    for (digit, code) in digits {
        table[digit] = (code, digit)
    }

    let functionKeys: [UInt32] = [
        0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,
        0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A,
    ]
    for (index, code) in functionKeys.enumerated() {
        table["f\(index + 1)"] = (code, "F\(index + 1)")
    }

    let named: [([String], UInt32, String)] = [
        (["grave", "backtick", "`"], 0x32, "`"),
        (["section", "§", "twosuperior", "²"], 0x0A, "§"),
        (["space"], 0x31, "Space"),
        (["tab"], 0x30, "⇥"),
        (["return", "enter"], 0x24, "↩"),
        (["escape", "esc"], 0x35, "⎋"),
        (["delete", "backspace"], 0x33, "⌫"),
        (["forwarddelete"], 0x75, "⌦"),
        (["minus", "-"], 0x1B, "-"),
        (["equal", "="], 0x18, "="),
        (["bracketleft", "["], 0x21, "["),
        (["bracketright", "]"], 0x1E, "]"),
        (["semicolon", ";"], 0x29, ";"),
        (["quote", "'"], 0x27, "'"),
        (["backslash", "\\"], 0x2A, "\\"),
        (["comma", ","], 0x2B, ","),
        (["period", "."], 0x2F, "."),
        (["slash", "/"], 0x2C, "/"),
        (["left"], 0x7B, "←"),
        (["right"], 0x7C, "→"),
        (["down"], 0x7D, "↓"),
        (["up"], 0x7E, "↑"),
        (["home"], 0x73, "↖"),
        (["end"], 0x77, "↘"),
        (["pageup"], 0x74, "⇞"),
        (["pagedown"], 0x79, "⇟"),
    ]
    for (aliases, code, name) in named {
        for alias in aliases {
            table[alias] = (code, name)
        }
    }
    return table
}()
