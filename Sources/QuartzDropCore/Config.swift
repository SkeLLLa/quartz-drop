import Foundation
import TOMLDecoder

public struct ConfigError: Error, LocalizedError, CustomStringConvertible, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
    public var errorDescription: String? { message }
}

public enum LogLevel: String, Sendable, Comparable {
    case off, error, warn, info, debug, trace

    private var rank: Int {
        switch self {
        case .off: 0
        case .error: 1
        case .warn: 2
        case .info: 3
        case .debug: 4
        case .trace: 5
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rank < rhs.rank }

    public static func parse(_ raw: String) throws -> LogLevel {
        let lower = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard let level = LogLevel(rawValue: lower) else {
            throw ConfigError(
                "invalid log_level '\(lower)' (expected error/warn/info/debug/trace/off)")
        }
        return level
    }
}

public enum AttachMode: String, Sendable {
    case find
    case findOrStart = "find-or-start"
}

public enum HideBehavior: String, Sendable {
    /// Hide the whole application, like ⌘H. Works for every app and leaves nothing on screen.
    case hide
    /// Minimize only the managed window into the Dock.
    case minimize
    /// Park only the managed window in the bottom-right screen corner.
    case offscreen
}

public enum PlacementMetric: Hashable, Sendable, CustomStringConvertible {
    case percent(Int)
    case pixels(Int)

    public var description: String {
        switch self {
        case .percent(let value): "\(value)%"
        case .pixels(let value): "\(value)px"
        }
    }
}

public enum PlacementPosition: String, Sendable {
    case topLeft = "top-left"
    case top
    case topRight = "top-right"
    case left
    case center
    case right
    case bottomLeft = "bottom-left"
    case bottom
    case bottomRight = "bottom-right"
}

public struct PlacementConfig: Hashable, Sendable {
    public var width: PlacementMetric = .percent(100)
    public var height: PlacementMetric = .percent(100)
    public var position: PlacementPosition = .topLeft
    public var offsetX: PlacementMetric = .pixels(0)
    public var offsetY: PlacementMetric = .pixels(0)
    public var screen: String?

    public init(
        width: PlacementMetric = .percent(100), height: PlacementMetric = .percent(100),
        position: PlacementPosition = .topLeft, offsetX: PlacementMetric = .pixels(0),
        offsetY: PlacementMetric = .pixels(0), screen: String? = nil
    ) {
        self.width = width
        self.height = height
        self.position = position
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.screen = screen
    }
}

public enum AnimationStyle: String, Sendable {
    case none, slide, fade
    case slideFade = "slide-fade"
}

public enum AnimationEasing: String, Sendable {
    case linear
    case easeOut = "ease-out"
    case easeInOut = "ease-in-out"
}

/// `[app.animation]`, validated like plasma-drop. Animations are not implemented yet.
public struct AnimationConfig: Hashable, Sendable {
    public var style: AnimationStyle = .none
    public var easing: AnimationEasing = .easeOut
    public var durationMs = 150
    public var frameDelayMs = 16

    public init(
        style: AnimationStyle = .none, easing: AnimationEasing = .easeOut, durationMs: Int = 150,
        frameDelayMs: Int = 16
    ) {
        self.style = style
        self.easing = easing
        self.durationMs = durationMs
        self.frameDelayMs = frameDelayMs
    }
}

/// How an app is started when `attach_mode = "find-or-start"` finds no window.
public enum LaunchSpec: Hashable, Sendable {
    /// Explicit argv from `command`.
    case command([String])
    /// Launch (or reopen) the application with this bundle identifier.
    case bundleID(String)
    /// Launch (or reopen) the `.app` bundle at this path.
    case application(path: String)
    /// Launch (or reopen) an application by name, like `open -a <name>`.
    case applicationName(String)
}

/// Case-insensitive regular expression matcher.
public struct Pattern: @unchecked Sendable, Hashable {
    public let source: String
    private let regex: NSRegularExpression

    public init(_ source: String) throws {
        self.source = source
        regex = try NSRegularExpression(pattern: source, options: [.caseInsensitive])
    }

    public func matches(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }

    public static func == (lhs: Pattern, rhs: Pattern) -> Bool { lhs.source == rhs.source }
    public func hash(into hasher: inout Hasher) { hasher.combine(source) }
}

public struct AppConfig: Hashable, Sendable {
    public var name: String
    public var hotkey: Hotkey
    public var bundleID: String?
    public var filename: String?
    public var launch: LaunchSpec?
    /// `arguments` passed to an app bundle when it is opened. For a bare executable they are
    /// already part of the `.command` argv.
    public var arguments: [String]
    public var processName: Pattern?
    public var windowTitle: Pattern?
    public var attachMode: AttachMode
    public var workingDirectory: String?
    public var hideBehavior: HideBehavior
    public var hideOnFocusLost: Bool
    public var placement: PlacementConfig
    public var animation: AnimationConfig

    public init(
        name: String, hotkey: Hotkey, bundleID: String? = nil, filename: String? = nil,
        launch: LaunchSpec? = nil, arguments: [String] = [], processName: Pattern? = nil,
        windowTitle: Pattern? = nil,
        attachMode: AttachMode = .findOrStart, workingDirectory: String? = nil,
        hideBehavior: HideBehavior = .hide, hideOnFocusLost: Bool = false,
        placement: PlacementConfig = PlacementConfig(),
        animation: AnimationConfig = AnimationConfig()
    ) {
        self.name = name
        self.hotkey = hotkey
        self.bundleID = bundleID
        self.filename = filename
        self.launch = launch
        self.arguments = arguments
        self.processName = processName
        self.windowTitle = windowTitle
        self.attachMode = attachMode
        self.workingDirectory = workingDirectory
        self.hideBehavior = hideBehavior
        self.hideOnFocusLost = hideOnFocusLost
        self.placement = placement
        self.animation = animation
    }
}

public struct Config: Sendable {
    public var apps: [AppConfig]
    public var logLevel: LogLevel
    public var menuBar: Bool
    /// Non-fatal problems worth fixing in the config.
    public var warnings: [String]
    /// plasma-drop options and values that do not apply on macOS and are ignored, so a plasma-drop
    /// config can be copied as is.
    public var ignored: [String]

    public static func load(path: String) throws -> Config {
        let text: String
        do {
            text = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw ConfigError("failed to read config '\(path)': \(error.localizedDescription)")
        }
        do {
            return try parse(text)
        } catch let error as ConfigError {
            throw ConfigError("invalid config '\(path)': \(error.message)")
        }
    }

    public static func parse(_ text: String) throws -> Config {
        let raw: RawConfig
        do {
            raw = try TOMLDecoder().decode(RawConfig.self, from: text)
        } catch {
            throw ConfigError("failed to parse TOML: \(error)")
        }
        return try from(raw)
    }

    public static func defaultPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/quartz-drop/config.toml"
    }

    private static func from(_ raw: RawConfig) throws -> Config {
        let apps = raw.apps ?? []
        guard !apps.isEmpty else {
            throw ConfigError("config must contain at least one [[app]] entry")
        }

        let logLevel = try raw.logLevel.map(LogLevel.parse) ?? .error
        var warnings: [String] = []
        var ignored: [String] = []
        var names = Set<String>()
        var hotkeys = Set<Hotkey.Identity>()
        var parsed: [AppConfig] = []

        for app in apps {
            let name = app.name.trimmingCharacters(in: .whitespaces)
            if name.isEmpty {
                throw ConfigError("app name must not be empty")
            }
            if name.count > 64 {
                throw ConfigError("app name '\(name)' exceeds 64 characters")
            }
            if !names.insert(name).inserted {
                throw ConfigError("duplicate app name '\(name)'")
            }

            if let key = Hotkey.unsupportedKey(in: app.hotkey) {
                ignored.append(
                    "app '\(name)': hotkey '\(app.hotkey)' (macOS has no \(key.uppercased()) key; app skipped)"
                )
                continue
            }

            let hotkey: Hotkey
            do {
                hotkey = try Hotkey.parse(app.hotkey)
            } catch let error as ConfigError {
                throw ConfigError("invalid hotkey for app '\(name)': \(error.message)")
            }
            if !hotkeys.insert(hotkey.identity).inserted {
                throw ConfigError("duplicate hotkey '\(hotkey.raw)'")
            }

            let bundleID = try nonBlank(app.bundleID, field: "bundle_id", app: name)
            let filename = try nonBlank(app.filename, field: "filename", app: name)
            if bundleID == nil && filename == nil && app.processName == nil
                && app.windowTitle == nil
            {
                throw ConfigError(
                    "app '\(name)' must set at least one of bundle_id, filename, process_name, or window_title"
                )
            }

            let attachMode: AttachMode = try value(
                app.attachMode, default: .findOrStart, field: "attach_mode", app: name)
            let hideBehavior: HideBehavior = try value(
                app.hideBehavior, default: .hide, field: "hide_behavior", app: name)

            let arguments = app.arguments ?? []
            if app.command != nil && !arguments.isEmpty {
                throw ConfigError("app '\(name)' cannot set both command and arguments")
            }
            let launch = try launchSpec(
                app: name, command: app.command, arguments: arguments, bundleID: bundleID,
                filename: filename)
            if attachMode == .findOrStart && launch == nil {
                // plasma-drop accepts this and fails only when it has to start the app.
                warnings.append(
                    "app '\(name)': attach_mode 'find-or-start' cannot start the app without command, bundle_id, or filename; it can only attach to a running window"
                )
            }

            var workingDirectory = app.workingDirectory
            if let dir = workingDirectory {
                if !dir.hasPrefix("/") {
                    throw ConfigError("app '\(name)' has non-absolute working_directory '\(dir)'")
                }
                var isDirectory: ObjCBool = false
                if !FileManager.default.fileExists(atPath: dir, isDirectory: &isDirectory)
                    || !isDirectory.boolValue
                {
                    // Likely a Linux path from a copied plasma-drop config.
                    ignored.append("app '\(name)': working_directory '\(dir)' does not exist")
                    workingDirectory = nil
                }
            }

            if app.hideDecorations != nil {
                ignored.append("app '\(name)': hide_decorations")
            }
            if app.followCurrentDesktop != nil {
                ignored.append(
                    "app '\(name)': follow_current_desktop (use the app's Dock menu: Options → Assign To → All Desktops)"
                )
            }
            let animation = try animationConfig(app.animation, app: name)
            if animation.style != .none {
                ignored.append("app '\(name)': animation style '\(animation.style.rawValue)'")
            }

            parsed.append(
                AppConfig(
                    name: name,
                    hotkey: hotkey,
                    bundleID: bundleID,
                    filename: filename,
                    launch: launch,
                    arguments: arguments,
                    processName: try pattern(app.processName, field: "process_name", app: name),
                    windowTitle: try pattern(app.windowTitle, field: "window_title", app: name),
                    attachMode: attachMode,
                    workingDirectory: workingDirectory,
                    hideBehavior: hideBehavior,
                    hideOnFocusLost: app.hideOnFocusLost ?? false,
                    placement: try placement(app.placement, app: name),
                    animation: animation
                ))
        }

        return Config(
            apps: parsed, logLevel: logLevel, menuBar: raw.menuBar ?? true,
            warnings: warnings, ignored: ignored)
    }

    private static func value<T: RawRepresentable>(
        _ raw: String?, default fallback: T, field: String, app: String
    ) throws -> T where T.RawValue == String {
        guard let raw else { return fallback }
        guard let parsed = T(rawValue: raw) else {
            throw ConfigError("app '\(app)' has invalid \(field) '\(raw)'")
        }
        return parsed
    }

    private static func nonBlank(_ value: String?, field: String, app: String) throws -> String? {
        guard let value else { return nil }
        if value.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ConfigError("app '\(app)' has empty \(field)")
        }
        return value
    }

    private static func pattern(_ raw: String?, field: String, app: String) throws -> Pattern? {
        guard let raw else { return nil }
        do {
            return try Pattern(raw)
        } catch {
            throw ConfigError("app '\(app)' has invalid \(field) regex '\(raw)'")
        }
    }

    private static func launchSpec(
        app: String, command: [String]?, arguments: [String], bundleID: String?, filename: String?
    ) throws -> LaunchSpec? {
        if let command {
            guard let program = command.first else {
                throw ConfigError("app '\(app)' has empty command")
            }
            if program.trimmingCharacters(in: .whitespaces).isEmpty {
                throw ConfigError("app '\(app)' has invalid command program")
            }
            return .command(command)
        }
        if let bundleID {
            return .bundleID(bundleID)
        }
        guard let filename else { return nil }
        if filename.contains("/") {
            return filename.lowercased().hasSuffix(".app")
                ? .application(path: filename) : .command([filename] + arguments)
        }
        return .applicationName(stripAppSuffix(filename))
    }

    private static func placement(_ raw: RawPlacementConfig?, app: String) throws
        -> PlacementConfig
    {
        guard let raw else { return PlacementConfig() }
        let position: PlacementPosition = try value(
            raw.position, default: .topLeft, field: "position", app: app)

        var screen: String?
        if let name = raw.screen {
            if name.isEmpty || name.trimmingCharacters(in: .whitespaces) != name {
                throw ConfigError("app '\(app)' has invalid screen '\(name)'")
            }
            screen = name
        }

        return PlacementConfig(
            width: try metric(raw.width ?? "100%", field: "width", app: app, kind: .size),
            height: try metric(raw.height ?? "100%", field: "height", app: app, kind: .size),
            position: position,
            offsetX: try metric(raw.offsetX ?? "0px", field: "offset_x", app: app, kind: .offset),
            offsetY: try metric(raw.offsetY ?? "0px", field: "offset_y", app: app, kind: .offset),
            screen: screen
        )
    }

    private static func animationConfig(_ raw: RawAnimationConfig?, app: String) throws
        -> AnimationConfig
    {
        guard let raw else { return AnimationConfig() }
        let style: AnimationStyle = try value(
            raw.style, default: .none, field: "animation.style", app: app)
        let easing: AnimationEasing = try value(
            raw.easing, default: .easeOut, field: "animation.easing", app: app)
        let duration = raw.durationMs ?? 150
        if duration < 0 {
            throw ConfigError("app '\(app)' has negative animation.duration_ms '\(duration)'")
        }
        if duration > 2_000 {
            throw ConfigError(
                "app '\(app)' has animation.duration_ms larger than 2000: '\(duration)'")
        }
        let frameDelay = raw.frameDelayMs ?? 16
        if frameDelay <= 0 || frameDelay > Int(UInt16.max) {
            throw ConfigError(
                "app '\(app)' has animation.frame_delay_ms that must be greater than 0")
        }
        return AnimationConfig(
            style: style, easing: easing, durationMs: duration, frameDelayMs: frameDelay)
    }

    private enum MetricKind {
        case size, offset
    }

    private static func metric(_ raw: String, field: String, app: String, kind: MetricKind) throws
        -> PlacementMetric
    {
        let invalid = ConfigError("app '\(app)' has invalid \(field) metric '\(raw)'")
        if raw.isEmpty || raw.trimmingCharacters(in: .whitespaces) != raw {
            throw invalid
        }

        let isPercent: Bool
        let value: Substring
        if raw.hasSuffix("%") {
            isPercent = true
            value = raw.dropLast()
        } else if raw.hasSuffix("px") {
            isPercent = false
            value = raw.dropLast(2)
        } else {
            throw invalid
        }
        guard !value.isEmpty, !value.contains(where: \.isWhitespace), let number = Int(value) else {
            throw invalid
        }

        if kind == .size && number <= 0 {
            throw ConfigError("app '\(app)' has non-positive \(field) metric '\(raw)'")
        }
        if isPercent {
            if kind == .size && number > 100 {
                throw ConfigError("app '\(app)' has \(field) percentage larger than 100: '\(raw)'")
            }
            if abs(number) > Int(Int16.max) {
                throw ConfigError("app '\(app)' has out-of-range \(field) metric '\(raw)'")
            }
            return .percent(number)
        }
        return .pixels(number)
    }
}

func stripAppSuffix(_ name: String) -> String {
    name.lowercased().hasSuffix(".app") ? String(name.dropLast(4)) : name
}

extension Hotkey {
    struct Identity: Hashable {
        let keyCode: UInt32
        let modifiers: UInt32
    }

    var identity: Identity { Identity(keyCode: keyCode, modifiers: modifiers.rawValue) }
}

// MARK: - Raw TOML schema

private struct RawConfig: Decodable {
    var apps: [RawAppConfig]?
    var logLevel: String?
    var menuBar: Bool?

    enum CodingKeys: String, CodingKey {
        case apps = "app"
        case logLevel = "log_level"
        case menuBar = "menu_bar"
    }
}

private struct RawAppConfig: Decodable {
    var name: String
    var hotkey: String
    var bundleID: String?
    var filename: String?
    var command: [String]?
    var arguments: [String]?
    var processName: String?
    var windowTitle: String?
    var attachMode: String?
    var workingDirectory: String?
    var hideBehavior: String?
    var hideOnFocusLost: Bool?
    var placement: RawPlacementConfig?
    // Accepted for plasma-drop config compatibility, then reported as unsupported.
    var hideDecorations: Bool?
    var followCurrentDesktop: Bool?
    var animation: RawAnimationConfig?

    enum CodingKeys: String, CodingKey {
        case name, hotkey, filename, command, arguments, placement, animation
        case bundleID = "bundle_id"
        case processName = "process_name"
        case windowTitle = "window_title"
        case attachMode = "attach_mode"
        case workingDirectory = "working_directory"
        case hideBehavior = "hide_behavior"
        case hideOnFocusLost = "hide_on_focus_lost"
        case hideDecorations = "hide_decorations"
        case followCurrentDesktop = "follow_current_desktop"
    }
}

private struct RawPlacementConfig: Decodable {
    var width: String?
    var height: String?
    var position: String?
    var offsetX: String?
    var offsetY: String?
    var screen: String?

    enum CodingKeys: String, CodingKey {
        case width, height, position, screen
        case offsetX = "offset_x"
        case offsetY = "offset_y"
    }
}

private struct RawAnimationConfig: Decodable {
    var style: String?
    var easing: String?
    var durationMs: Int?
    var frameDelayMs: Int?

    enum CodingKeys: String, CodingKey {
        case style, easing
        case durationMs = "duration_ms"
        case frameDelayMs = "frame_delay_ms"
    }
}
