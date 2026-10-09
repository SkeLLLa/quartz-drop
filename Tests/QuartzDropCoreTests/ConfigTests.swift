import Foundation
import Testing

@testable import QuartzDropCore

@Suite struct ConfigTests {
    func app(
        _ extra: String = "", name: String = "a", hotkey: String = "ctrl+a",
        identity: String = "bundle_id = \"com.test.a\""
    ) -> String {
        """
        [[app]]
        name = "\(name)"
        hotkey = "\(hotkey)"
        \(identity)
        \(extra)

        """
    }

    func expectError(
        _ toml: String, contains text: String, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let error = try #require(throws: ConfigError.self, sourceLocation: sourceLocation) {
            try Config.parse(toml)
        }
        #expect(
            error.message.contains(text), "got: \(error.message)", sourceLocation: sourceLocation)
    }

    @Test func minimalConfig() throws {
        let config = try Config.parse(app())
        #expect(config.apps.count == 1)
        #expect(config.apps[0].name == "a")
        #expect(config.apps[0].bundleID == "com.test.a")
        #expect(config.warnings.isEmpty)
    }

    @Test func defaults() throws {
        let config = try Config.parse(app())
        #expect(config.logLevel == .error)
        #expect(config.menuBar)
        let a = config.apps[0]
        #expect(a.attachMode == .findOrStart)
        #expect(a.hideBehavior == .hide)
        #expect(!a.hideOnFocusLost)
        #expect(a.placement.width == .percent(100))
        #expect(a.placement.height == .percent(100))
        #expect(a.placement.position == .topLeft)
        #expect(a.placement.offsetX == .pixels(0))
        #expect(a.placement.offsetY == .pixels(0))
        #expect(a.placement.screen == nil)
        #expect(a.workingDirectory == nil)
    }

    @Test func topLevelOptions() throws {
        let config = try Config.parse(
            "log_level = \"Debug\"\nmenu_bar = false\n" + app())
        #expect(config.logLevel == .debug)
        #expect(!config.menuBar)
        try expectError("log_level = \"loud\"\n" + app(), contains: "invalid log_level")
    }

    @Test func fullPlacement() throws {
        let toml = app(
            """
            hide_behavior = "offscreen"
            hide_on_focus_lost = true
            attach_mode = "find"
            [app.placement]
            width = "50%"
            height = "300px"
            position = "bottom-right"
            offset_x = "-10px"
            offset_y = "5%"
            screen = "DELL"
            """)
        let a = try Config.parse(toml).apps[0]
        #expect(a.hideBehavior == .offscreen)
        #expect(a.hideOnFocusLost)
        #expect(a.attachMode == .find)
        #expect(
            a.placement
                == PlacementConfig(
                    width: .percent(50), height: .pixels(300), position: .bottomRight,
                    offsetX: .pixels(-10), offsetY: .percent(5), screen: "DELL"))
    }

    @Test func errorsNoApps() throws {
        try expectError("", contains: "at least one [[app]]")
        try expectError("log_level = \"info\"", contains: "at least one [[app]]")
    }

    @Test func errorsName() throws {
        try expectError(app(name: ""), contains: "must not be empty")
        try expectError(app(name: "   "), contains: "must not be empty")
        try expectError(app(name: String(repeating: "x", count: 65)), contains: "exceeds 64")
        #expect(throws: Never.self) {
            _ = try Config.parse(app(name: String(repeating: "x", count: 64)))
        }
    }

    @Test func errorsDuplicates() throws {
        try expectError(
            app(name: "a", hotkey: "ctrl+a") + app(name: "a", hotkey: "ctrl+b"),
            contains: "duplicate app name")
        try expectError(
            app(name: "a", hotkey: "ctrl+a") + app(name: "b", hotkey: "control+A"),
            contains: "duplicate hotkey")
        try expectError(
            app(name: "a", hotkey: "ctrl+alt+a") + app(name: "b", hotkey: "option+ctrl+a"),
            contains: "duplicate hotkey")
    }

    @Test func invalidHotkeyMentionsApp() throws {
        try expectError(app(hotkey: "ctrl+zzz"), contains: "invalid hotkey for app 'a'")
    }

    @Test func errorsMissingIdentity() throws {
        try expectError(app(identity: ""), contains: "at least one of bundle_id")
        try expectError(app(identity: "bundle_id = \"  \""), contains: "empty bundle_id")
        try expectError(app(identity: "filename = \"\""), contains: "empty filename")
    }

    @Test func findOrStartWithoutLaunchSpecWarns() throws {
        // plasma-drop accepts this and fails only when it has to start the app.
        let config = try Config.parse(app(identity: "process_name = \"x\""))
        #expect(config.apps[0].launch == nil)
        #expect(config.warnings.contains { $0.contains("find-or-start") })
        let find = try Config.parse(app("attach_mode = \"find\"", identity: "window_title = \"x\""))
        #expect(find.warnings.isEmpty)
    }

    @Test func arguments() throws {
        let path = try Config.parse(
            app("arguments = [\"--one\", \"two\"]", identity: "filename = \"/usr/local/bin/kitty\"")
        )
        #expect(path.apps[0].launch == .command(["/usr/local/bin/kitty", "--one", "two"]))
        let bundle = try Config.parse(app("arguments = [\"--one\"]")).apps[0]
        #expect(bundle.launch == .bundleID("com.test.a"))
        #expect(bundle.arguments == ["--one"])
        try expectError(
            app("command = [\"/bin/x\"]\narguments = [\"--one\"]"),
            contains: "cannot set both command and arguments")
    }

    @Test func animation() throws {
        let a = try Config.parse(
            app(
                """
                [app.animation]
                style = "slide-fade"
                easing = "ease-in-out"
                duration_ms = 220
                frame_delay_ms = 8
                """)
        ).apps[0]
        #expect(
            a.animation
                == AnimationConfig(
                    style: .slideFade, easing: .easeInOut, durationMs: 220, frameDelayMs: 8))
        #expect(try Config.parse(app()).apps[0].animation == AnimationConfig())
        // style = "none" is valid and needs no warning.
        #expect(
            try Config.parse(app("[app.animation]\nstyle = \"none\"\nduration_ms = 0")).ignored
                .isEmpty)
        try expectError(
            app("[app.animation]\nstyle = \"bounce\""), contains: "invalid animation.style")
        try expectError(
            app("[app.animation]\neasing = \"bounce\""), contains: "invalid animation.easing")
        try expectError(app("[app.animation]\nduration_ms = 2001"), contains: "larger than 2000")
        try expectError(app("[app.animation]\nframe_delay_ms = 0"), contains: "greater than 0")
    }

    /// plasma-drop's resources/example-config.toml, copied verbatim.
    @Test func acceptsPlasmaDropExampleConfig() throws {
        let config = try Config.parse(plasmaDropExample)
        #expect(config.apps.map(\.name) == ["dolphin", "kate", "okular", "chromium-flatpak"])
        #expect(config.apps[0].hotkey.modifiers == .command)
        #expect(config.apps[0].hideBehavior == .minimize)
        #expect(config.apps[1].hideBehavior == .offscreen)
        #expect(config.apps[3].launch?.isCommand == true)
        #expect(config.apps[2].animation.style == .slideFade)
        #expect(config.warnings.isEmpty)
    }

    @Test func errorsInvalidEnums() throws {
        try expectError(app("attach_mode = \"nope\""), contains: "invalid attach_mode 'nope'")
        try expectError(app("hide_behavior = \"nope\""), contains: "invalid hide_behavior 'nope'")
        try expectError(app("[app.placement]\nposition = \"middle\""), contains: "invalid position")
    }

    @Test func invalidMetrics() throws {
        for bad in ["50", " 50%", "50% ", "", "abc", "5 0%", "px", "%", "1.5%"] {
            try expectError(
                app("[app.placement]\nwidth = \"\(bad)\""), contains: "invalid width metric")
        }
        try expectError(app("[app.placement]\nwidth = \"0%\""), contains: "non-positive width")
        try expectError(app("[app.placement]\nwidth = \"-5px\""), contains: "non-positive width")
        try expectError(app("[app.placement]\nheight = \"0px\""), contains: "non-positive height")
        try expectError(app("[app.placement]\nwidth = \"101%\""), contains: "larger than 100")
        try expectError(
            app("[app.placement]\noffset_x = \"abc\""), contains: "invalid offset_x metric")
        try expectError(app("[app.placement]\nscreen = \" x\""), contains: "invalid screen")
        try expectError(app("[app.placement]\nscreen = \"\""), contains: "invalid screen")
    }

    @Test func validMetrics() throws {
        let a = try Config.parse(
            app(
                "[app.placement]\nwidth = \"1px\"\nheight = \"100%\"\noffset_x = \"-50%\"\noffset_y = \"-3px\""
            )
        )
        .apps[0]
        #expect(a.placement.width == .pixels(1))
        #expect(a.placement.height == .percent(100))
        #expect(a.placement.offsetX == .percent(-50))
        #expect(a.placement.offsetY == .pixels(-3))
    }

    @Test func invalidRegex() throws {
        try expectError(app("process_name = \"(\""), contains: "invalid process_name regex")
        try expectError(app("window_title = \"[\""), contains: "invalid window_title regex")
    }

    @Test func workingDirectory() throws {
        try expectError(
            app("working_directory = \"relative/dir\""), contains: "non-absolute working_directory")
        let missing = try Config.parse(app("working_directory = \"/definitely/not/here-xyz\""))
        #expect(missing.apps[0].workingDirectory == nil)
        #expect(missing.ignored.contains { $0.contains("does not exist") })
        let a = try Config.parse(app("working_directory = \"/tmp\"")).apps[0]
        #expect(a.workingDirectory == "/tmp")
        // A file is not a directory.
        #expect(
            try Config.parse(app("working_directory = \"/etc/hosts\"")).apps[0].workingDirectory
                == nil)
    }

    @Test func launchFromCommand() throws {
        let a = try Config.parse(
            app(
                "command = [\"kitty\", \"--single-instance\"]", identity: "process_name = \"kitty\""
            )
        ).apps[0]
        guard case .command(let argv)? = a.launch else {
            Issue.record("expected .command, got \(String(describing: a.launch))")
            return
        }
        #expect(argv == ["kitty", "--single-instance"])
        try expectError(app("command = []"), contains: "empty command")
        try expectError(app("command = [\"  \"]"), contains: "invalid command program")
    }

    @Test func commandBeatsBundleID() throws {
        let a = try Config.parse(app("command = [\"x\"]")).apps[0]
        #expect(a.launch == .command(["x"]))
    }

    @Test func launchFromBundleID() throws {
        #expect(try Config.parse(app()).apps[0].launch == .bundleID("com.test.a"))
    }

    @Test func launchFromFilename() throws {
        func launch(_ filename: String) throws -> LaunchSpec? {
            try Config.parse(app(identity: "filename = \"\(filename)\"")).apps[0].launch
        }
        #expect(
            try launch("/Applications/Safari.app") == .application(path: "/Applications/Safari.app")
        )
        #expect(try launch("/usr/local/bin/kitty") == .command(["/usr/local/bin/kitty"]))
        #expect(try launch("Safari.app") == .applicationName("Safari"))
        #expect(try launch("Safari") == .applicationName("Safari"))
        #expect(
            try launch("/Applications/SAFARI.APP") == .application(path: "/Applications/SAFARI.APP")
        )
    }

    @Test func ignoresUnsupportedOptions() throws {
        let config = try Config.parse(
            app(
                """
                hide_decorations = true
                follow_current_desktop = true
                [app.animation]
                style = "slide"
                """))
        #expect(config.warnings.isEmpty)
        #expect(config.ignored.count == 3)
        #expect(config.ignored.contains { $0.contains("hide_decorations") })
        #expect(config.ignored.contains { $0.contains("follow_current_desktop") })
        #expect(config.ignored.contains { $0.contains("animation") })
    }

    @Test func unsupportedFunctionKeySkipsApp() throws {
        let config = try Config.parse(
            app(name: "plasma", hotkey: "super+f22", identity: "bundle_id = \"com.test.p\"")
                + app(name: "b", hotkey: "ctrl+b"))
        #expect(config.apps.count == 1)
        #expect(config.apps[0].name == "b")
        #expect(config.ignored.contains { $0.contains("macOS has no F22 key") })
    }

    @Test func malformedToml() throws {
        try expectError("[[app]\nname=", contains: "failed to parse TOML")
        // hotkey missing
        try expectError("[[app]]\nname = \"a\"", contains: "failed to parse TOML")
    }

    @Test func loadReportsPath() throws {
        let missing = try #require(throws: ConfigError.self) {
            try Config.load(path: "/definitely/not/here.toml")
        }
        #expect(missing.message.contains("failed to read config"))
        let path = NSTemporaryDirectory() + "quartzdrop-test-\(UUID().uuidString).toml"
        defer { try? FileManager.default.removeItem(atPath: path) }
        try "".write(toFile: path, atomically: true, encoding: .utf8)
        let invalid = try #require(throws: ConfigError.self) { try Config.load(path: path) }
        #expect(invalid.message.contains("invalid config"))
        #expect(invalid.message.contains(path))
        try app().write(toFile: path, atomically: true, encoding: .utf8)
        #expect(try Config.load(path: path).apps.count == 1)
    }

    @Test func logLevelOrderingAndParse() throws {
        #expect(LogLevel.error < .warn)
        #expect(LogLevel.trace > .debug)
        #expect(LogLevel.off < .error)
        #expect(try LogLevel.parse(" WARN ") == .warn)
    }

    @Test func patternIsCaseInsensitive() throws {
        let p = try Pattern("^foo")
        #expect(p.matches("FOObar"))
        #expect(!p.matches("xfoo"))
    }
}

extension LaunchSpec {
    var isCommand: Bool {
        if case .command = self { return true }
        return false
    }
}

private let plasmaDropExample = #"""
    # log_level = "error"  # error | warn | info | debug | trace | off (default: error)
    #                        # Override with --log-level CLI flag or RUST_LOG env var.

    [[app]]
    name = "dolphin"
    hotkey = "super+f9"
    filename = "/usr/bin/dolphin"
    attach_mode = "find-or-start"
    hide_decorations = true
    hide_behavior = "minimize"
    hide_on_focus_lost = true
    follow_current_desktop = true

    [app.placement]
    width = "50%"
    height = "100%"
    position = "left"
    # screen = "eDP-1"

    [app.animation]
    style = "slide"
    easing = "ease-out"
    duration_ms = 1000
    frame_delay_ms = 8

    [[app]]
    name = "kate"
    hotkey = "super+f7"
    filename = "/usr/bin/kate"
    attach_mode = "find-or-start"
    hide_behavior = "offscreen"

    [app.placement]
    width = "50%"
    height = "100%"
    position = "center"

    [app.animation]
    style = "fade"
    easing = "ease-in-out"
    duration_ms = 1000

    [[app]]
    name = "okular"
    hotkey = "super+f8"
    filename = "/usr/bin/okular"
    attach_mode = "find-or-start"

    [app.placement]
    width = "66%"
    height = "100%"
    position = "right"

    [app.animation]
    style = "slide-fade"
    easing = "linear"
    duration_ms = 1000

    [[app]]
    name = "chromium-flatpak"
    hotkey = "super+f6"
    filename = "io.github.ungoogled_software.ungoogled_chromium"
    process_name = "io\\.github\\.ungoogled_software\\.ungoogled_chromium|chromium|chrome"
    command = [
      "/usr/bin/flatpak",
      "run",
      "--branch=stable",
      "--arch=x86_64",
      "--command=/app/bin/chromium",
      "--file-forwarding",
      "io.github.ungoogled_software.ungoogled_chromium",
      "@@u",
      "%U",
      "@@",
    ]
    attach_mode = "find-or-start"

    [app.placement]
    width = "50%"
    height = "100%"
    position = "left"

    [app.animation]
    style = "none"
    easing = "ease-out"
    duration_ms = 0
    """#
