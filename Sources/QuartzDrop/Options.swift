import Foundation
import QuartzDropCore

struct Options {
    enum Command: Equatable {
        case run
        case initConfig(force: Bool)
        case printExampleConfig
        case check
        case version
        case help
    }

    var command: Command = .run
    var configPath: String?
    var verbosity = 0
    var logLevel: LogLevel?

    static let usage = """
        quartz-drop \(appVersion): toggle macOS apps with global hotkeys

        USAGE:
            quartz-drop [OPTIONS] [COMMAND]

        COMMANDS:
            (none)                  Run in the background (menu bar app)
            init [--force]          Write the example config to the config path
            print-example-config    Print the example config to stdout
            check                   Validate the config and exit

        OPTIONS:
            -c, --config <PATH>     Config file (default: ~/.config/quartz-drop/config.toml)
            -v, -vv                 Log at info / debug level
                --log-level <LEVEL> error | warn | info | debug | trace | off
            -V, --version           Print version
            -h, --help              Print help

        ENVIRONMENT:
            QUARTZ_DROP_LOG         Log level; overrides flags and the config
        """

    /// The config file to use: `--config` if given, otherwise the default path.
    var resolvedConfigPath: String { configPath ?? Config.defaultPath() }

    private static func absoluteConfigPath(_ path: String) -> String {
        absolutePath(
            path, currentDirectory: FileManager.default.currentDirectoryPath,
            home: NSHomeDirectory())
    }

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var iterator = arguments.makeIterator()
        var sawCommand = false

        func value(for flag: String) throws -> String {
            guard let value = iterator.next() else {
                throw ConfigError("\(flag) requires a value")
            }
            return value
        }

        while let argument = iterator.next() {
            switch argument {
            // Finder passes a process serial number when launching old-style bundles.
            case _ where argument.hasPrefix("-psn_"):
                continue
            case "-c", "--config":
                options.configPath = absoluteConfigPath(try value(for: argument))
            case _ where argument.hasPrefix("--config="):
                options.configPath = absoluteConfigPath(
                    String(argument.dropFirst("--config=".count)))
            case "-v":
                options.verbosity += 1
            case "-vv":
                options.verbosity += 2
            case "--log-level":
                options.logLevel = try LogLevel.parse(try value(for: argument))
            case _ where argument.hasPrefix("--log-level="):
                options.logLevel = try LogLevel.parse(
                    String(argument.dropFirst("--log-level=".count)))
            case "-V", "--version":
                options.command = .version
            case "-h", "--help":
                options.command = .help
            case "--force":
                guard case .initConfig = options.command else {
                    throw ConfigError("--force is only valid with init")
                }
                options.command = .initConfig(force: true)
            case "init", "print-example-config", "check":
                if sawCommand {
                    throw ConfigError("unexpected argument '\(argument)'")
                }
                sawCommand = true
                options.command =
                    switch argument {
                    case "init": .initConfig(force: false)
                    case "check": .check
                    default: .printExampleConfig
                    }
            default:
                throw ConfigError("unexpected argument '\(argument)'")
            }
        }
        return options
    }

    /// Log level precedence: `QUARTZ_DROP_LOG`, then `--log-level` / `-v`, then the config.
    func effectiveLogLevel(config: LogLevel?) -> LogLevel {
        if let env = ProcessInfo.processInfo.environment["QUARTZ_DROP_LOG"],
            let level = try? LogLevel.parse(env)
        {
            return level
        }
        if let logLevel {
            return logLevel
        }
        switch verbosity {
        case 0: break
        case 1: return .info
        default: return .debug
        }
        return config ?? .error
    }
}
