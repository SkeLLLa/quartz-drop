import Foundation
import os

/// Process-wide logger writing to the unified log (subsystem `ua.SkeLLLa.QuartzDrop`) and, when
/// attached to a terminal, to stderr.
public enum Log {
    public static let subsystem = "ua.SkeLLLa.QuartzDrop"

    private static let state = OSAllocatedUnfairLock(initialState: LogLevel.error)
    private static let logger = Logger(subsystem: subsystem, category: "main")
    private static let toStderr = isatty(STDERR_FILENO) == 1

    public static var level: LogLevel {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    public static func error(_ message: @autoclosure () -> String) { write(.error, message) }
    public static func warn(_ message: @autoclosure () -> String) { write(.warn, message) }
    public static func info(_ message: @autoclosure () -> String) { write(.info, message) }
    public static func debug(_ message: @autoclosure () -> String) { write(.debug, message) }
    public static func trace(_ message: @autoclosure () -> String) { write(.trace, message) }

    private static func write(_ messageLevel: LogLevel, _ message: () -> String) {
        guard messageLevel <= level else { return }
        let text = message()
        switch messageLevel {
        case .error: logger.error("\(text, privacy: .public)")
        case .warn: logger.warning("\(text, privacy: .public)")
        case .info: logger.info("\(text, privacy: .public)")
        case .debug, .trace, .off: logger.debug("\(text, privacy: .public)")
        }
        if toStderr {
            let tag = messageLevel.rawValue.uppercased().padding(
                toLength: 5, withPad: " ", startingAt: 0)
            FileHandle.standardError.write(Data("\(tag) \(text)\n".utf8))
        }
    }
}
