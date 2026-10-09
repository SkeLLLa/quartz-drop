import Testing

@testable import QuartzDropCore

@Suite struct HotkeyTests {
    @Test func parsesSimpleKey() throws {
        let hotkey = try Hotkey.parse("a")
        #expect(hotkey.keyCode == 0x00)
        #expect(hotkey.modifiers.isEmpty)
        #expect(hotkey.keyName == "A")
    }

    @Test(arguments: [
        ("ctrl", HotkeyModifiers.control), ("control", .control),
        ("alt", .option), ("option", .option), ("opt", .option),
        ("cmd", .command), ("command", .command), ("super", .command), ("meta", .command),
        ("win", .command), ("shift", .shift),
    ])
    func modifierAliases(alias: String, expected: HotkeyModifiers) throws {
        let hotkey = try Hotkey.parse("\(alias)+a")
        #expect(hotkey.modifiers == expected)
    }

    @Test(arguments: [
        ("a", UInt32(0x00)), ("f", 0x03), ("grave", 0x32), ("`", 0x32), ("backtick", 0x32),
        ("space", 0x31), ("f1", 0x7A), ("f12", 0x6F), ("f20", 0x5A),
        ("left", 0x7B), ("right", 0x7C), ("down", 0x7D), ("up", 0x7E),
        ("1", 0x12), ("0", 0x1D), ("return", 0x24), ("esc", 0x35),
    ])
    func keyCodes(key: String, code: UInt32) throws {
        #expect(try Hotkey.parse("ctrl+\(key)").keyCode == code)
    }

    @Test func allModifiersCombine() throws {
        let hotkey = try Hotkey.parse("ctrl+alt+shift+cmd+f")
        #expect(hotkey.modifiers == [.control, .option, .shift, .command])
        #expect(hotkey.keyCode == 0x03)
    }

    @Test func displayUsesGlyphOrder() throws {
        #expect(try Hotkey.parse("cmd+shift+alt+ctrl+f").display == "⌃⌥⇧⌘F")
        #expect(try Hotkey.parse("ctrl+alt+f").display == "⌃⌥F")
        #expect(try Hotkey.parse("cmd+space").display == "⌘Space")
        #expect(try Hotkey.parse("f5").display == "F5")
        #expect(try Hotkey.parse("shift+left").display == "⇧←")
    }

    @Test func caseAndWhitespaceInsensitive() throws {
        let hotkey = try Hotkey.parse("  Ctrl + ALT + F  ")
        #expect(hotkey.modifiers == [.control, .option])
        #expect(hotkey.keyCode == 0x03)
        #expect(hotkey.raw == "Ctrl + ALT + F")
        #expect(try Hotkey.parse("CONTROL+Space").keyCode == 0x31)
    }

    @Test func modifierOrderDoesNotMatter() throws {
        let a = try Hotkey.parse("ctrl+alt+a")
        let b = try Hotkey.parse("alt+ctrl+a")
        #expect(a.modifiers == b.modifiers)
        #expect(a.keyCode == b.keyCode)
    }

    @Test(
        arguments: [
            ("", "must not be empty"),
            ("   ", "must not be empty"),
            ("+", "must not be empty"),
            ("hyper+a", "unknown hotkey modifier 'hyper'"),
            ("ctrl+nonsense", "unknown hotkey key 'nonsense'"),
            ("ctrl+control+a", "duplicate hotkey modifier"),
            ("cmd+super+a", "duplicate hotkey modifier"),
            ("ctrl+", "unknown hotkey key"),
        ])
    func errors(input: String, text: String) throws {
        let error = try #require(throws: ConfigError.self) { try Hotkey.parse(input) }
        #expect(error.message.contains(text), "got: \(error.message)")
    }

    @Test func unsupportedFunctionKeys() {
        #expect(Hotkey.unsupportedKey(in: "super+f22") == "f22")
        #expect(Hotkey.unsupportedKey(in: "ctrl + F24 ") == "f24")
        #expect(Hotkey.unsupportedKey(in: "ctrl+f20") == nil)
        #expect(Hotkey.unsupportedKey(in: "ctrl+a") == nil)
    }
}
