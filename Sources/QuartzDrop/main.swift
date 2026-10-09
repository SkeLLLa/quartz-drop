import AppKit
import QuartzDropCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let options: Options
do {
    options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    fail("\(error.localizedDescription)\n\n\(Options.usage)")
}
Log.level = options.effectiveLogLevel(config: nil)
let configPath = options.resolvedConfigPath

switch options.command {
case .help:
    print(Options.usage)
case .version:
    print("quartz-drop \(appVersion)")
case .printExampleConfig:
    print(exampleConfig)
case .initConfig(let force):
    do {
        try writeExampleConfig(to: configPath, force: force)
        print("wrote example config to \(configPath)")
    } catch {
        fail(error.localizedDescription)
    }
case .check:
    do {
        let config = try Config.load(path: configPath)
        for warning in config.warnings {
            print("warning: \(warning)")
        }
        for option in config.ignored {
            print("ignored on macOS: \(option)")
        }
        print("config '\(configPath)' is valid (\(config.apps.count) apps)")
    } catch {
        fail(error.localizedDescription)
    }
case .run:
    if let bundleID = Bundle.main.bundleIdentifier,
        let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })
    {
        FileHandle.standardError.write(
            Data(
                "quartz-drop is already running (pid \(other.processIdentifier)); opening its Settings\n"
                    .utf8))
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-b", bundleID]
        try? open.run()
        open.waitUntilExit()
        exit(0)
    }
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate(options: options)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

func writeExampleConfig(to path: String, force: Bool) throws {
    let fm = FileManager.default
    if fm.fileExists(atPath: path) && !force {
        throw ConfigError("config '\(path)' already exists; pass --force to overwrite it")
    }
    let directory = (path as NSString).deletingLastPathComponent
    try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
    try (exampleConfig + "\n").write(toFile: path, atomically: true, encoding: .utf8)
}
