import Foundation

public typealias WindowID = UInt32

/// Identity of a running application as macOS reports it.
public struct AppIdentity: Hashable, Sendable {
    public var pid: Int32
    /// `CFBundleIdentifier`, e.g. `com.apple.Safari`; empty for bare executables.
    public var bundleID: String
    /// Localized application name, e.g. `Safari`.
    public var name: String
    /// Executable file name, e.g. `Safari` or `kitty`.
    public var executableName: String

    public init(pid: Int32, bundleID: String, name: String, executableName: String) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.executableName = executableName
    }

    var fields: [String] { [bundleID, name, executableName] }
}

public struct WindowInfo: Hashable, Sendable {
    public var id: WindowID
    public var app: AppIdentity
    public var title: String
    public var frame: Rect
    public var isMinimized: Bool

    public init(id: WindowID, app: AppIdentity, title: String, frame: Rect, isMinimized: Bool) {
        self.id = id
        self.app = app
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
    }
}

extension AppConfig {
    /// Whether windows of `app` can match this config, ignoring `window_title`.
    ///
    /// `bundle_id` always filters. `process_name` matches the bundle ID, app name, or executable
    /// name. `filename` is a plain case-insensitive identity matcher used only when neither
    /// `process_name` nor `window_title` is set, mirroring plasma-drop.
    public func matchesApp(_ app: AppIdentity) -> Bool {
        if let bundleID, app.bundleID.caseInsensitiveCompare(bundleID) != .orderedSame {
            return false
        }
        if let processName {
            return app.fields.contains { !$0.isEmpty && processName.matches($0) }
        }
        if windowTitle != nil || bundleID != nil {
            return true
        }
        guard let filename else { return false }
        let needle = normalizedFilename(filename)
        return app.fields.contains { $0.lowercased() == needle }
    }

    public func matches(_ window: WindowInfo) -> Bool {
        guard matchesApp(window.app) else { return false }
        return windowTitle?.matches(window.title) ?? true
    }
}

/// Returns the first matching window, preferring windows that are not minimized, and the total
/// number of matches so callers can report ambiguity.
public func findBestMatch(_ windows: [WindowInfo], for app: AppConfig) -> (WindowInfo?, Int) {
    let matches = windows.filter(app.matches)
    let best = matches.first { !$0.isMinimized } ?? matches.first
    return (best, matches.count)
}

private func normalizedFilename(_ filename: String) -> String {
    let base = (filename as NSString).lastPathComponent
    return stripAppSuffix(base.isEmpty ? filename : base).lowercased()
}
