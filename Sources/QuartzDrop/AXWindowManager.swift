import AppKit
import ApplicationServices
import QuartzDropCore

/// Private but long-stable API (used by Rectangle, yabai, AltTab) that maps an AX window to its
/// CoreGraphics window number.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>)
    -> AXError

struct AXFailure: Error, CustomStringConvertible {
    let action: String
    let code: AXError

    var description: String {
        let hint =
            code == .apiDisabled || code == .cannotComplete && !AXIsProcessTrusted()
            ? " (grant quartz-drop Accessibility access in System Settings → Privacy & Security)"
            : ""
        return "\(action) failed with AXError \(code.rawValue)\(hint)"
    }
}

/// `WindowManaging` backed by the macOS Accessibility API and NSWorkspace.
@MainActor
final class AXWindowManager: WindowManaging {
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    /// AX elements of windows seen recently, so a lookup by id does not have to walk every app
    /// (each of which may take up to the messaging timeout when hung).
    private var cache: [WindowID: (element: AXUIElement, app: AppIdentity)] = [:]

    func runningApps() -> [AppIdentity] {
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> AppIdentity? in
            // Accessory (Dock-hidden) apps own regular windows too; only background-only
            // processes are skipped.
            guard app.activationPolicy != .prohibited, app.processIdentifier != ownPID else {
                return nil
            }
            return identity(of: app)
        }
        let pids = Set(apps.map(\.pid))
        cache = cache.filter { pids.contains($0.value.app.pid) }
        return apps
    }

    func windows(of app: AppIdentity) -> [WindowInfo] {
        let element = appElement(app.pid)
        guard let windows: [AXUIElement] = attribute(element, kAXWindowsAttribute) else {
            return []
        }
        let infos = windows.compactMap { window -> WindowInfo? in
            guard let info = info(for: window, app: app) else { return nil }
            cache[info.id] = (window, app)
            return info
        }
        let listed = Set(infos.map(\.id))
        cache = cache.filter { $0.value.app.pid != app.pid || listed.contains($0.key) }
        return infos
    }

    func window(id: WindowID) -> WindowInfo? {
        guard let (element, app) = lookup(id) else { return nil }
        return info(for: element, app: app)
    }

    func activeWindow() -> WindowInfo? {
        guard let running = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = appElement(running.processIdentifier)
        guard let window: AXUIElement = attribute(element, kAXFocusedWindowAttribute) else {
            return nil
        }
        let app = identity(of: running)
        guard let info = info(for: window, app: app) else { return nil }
        cache[info.id] = (window, app)
        return info
    }

    func frontmostPID() -> Int32? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    func cursorPosition() -> Point? {
        // NSEvent uses bottom-left origin coordinates; AX uses top-left of the primary display.
        let location = NSEvent.mouseLocation
        guard let primary = NSScreen.screens.first else { return nil }
        return Point(x: Int(location.x), y: Int(primary.frame.maxY - location.y))
    }

    func screens() -> [ScreenInfo] {
        guard let primary = NSScreen.screens.first else { return [] }
        let height = primary.frame.maxY
        func flip(_ rect: NSRect) -> Rect {
            Rect(
                x: Int(rect.minX.rounded()), y: Int((height - rect.maxY).rounded()),
                width: Int(rect.width.rounded()), height: Int(rect.height.rounded()))
        }
        return NSScreen.screens.map {
            ScreenInfo(
                name: $0.localizedName, frame: flip($0.frame), visibleFrame: flip($0.visibleFrame))
        }
    }

    func setFrame(_ frame: Rect, of window: WindowID) throws {
        let (element, app) = try require(window)
        // Enhanced UI (enabled by VoiceOver and some utilities) animates and fights AX moves.
        let appElement = appElement(app.pid)
        let enhanced: Bool = attribute(appElement, "AXEnhancedUserInterface") ?? false
        if enhanced {
            AXUIElementSetAttributeValue(
                appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }
        defer {
            if enhanced {
                AXUIElementSetAttributeValue(
                    appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }
        }

        var point = CGPoint(x: frame.x, y: frame.y)
        var size = CGSize(width: frame.width, height: frame.height)
        let position = AXValueCreate(.cgPoint, &point)
        let sizeValue = AXValueCreate(.cgSize, &size)
        var settable: DarwinBoolean = false
        let checked = AXUIElementIsAttributeSettable(
            element, kAXSizeAttribute as CFString, &settable)
        if checked == .success, !settable.boolValue {
            Log.info("window \(window) of \(app.name) has a fixed size; moving it without resizing")
            try set(element, kAXPositionAttribute, position, action: "moving window")
            return
        }

        // Size, move, size again: macOS clamps a size that does not fit at the old position, and
        // refuses a position that would push the old size off screen.
        try set(element, kAXSizeAttribute, sizeValue, action: "resizing window")
        try set(element, kAXPositionAttribute, position, action: "moving window")
        try set(element, kAXSizeAttribute, sizeValue, action: "resizing window")
    }

    func focus(_ window: WindowID) throws {
        let (element, app) = try require(window)
        activate(pid: app.pid)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        let result = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        if result != .success {
            throw AXFailure(action: "raising window", code: result)
        }
    }

    func setMinimized(_ minimized: Bool, window: WindowID) throws {
        let (element, _) = try require(window)
        let value = minimized ? kCFBooleanTrue : kCFBooleanFalse
        let result = AXUIElementSetAttributeValue(
            element, kAXMinimizedAttribute as CFString, value as CFTypeRef)
        if result != .success {
            throw AXFailure(
                action: minimized ? "minimizing window" : "restoring window", code: result)
        }
    }

    func setHidden(_ hidden: Bool, pid: Int32) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if hidden {
            app.hide()
        } else {
            app.unhide()
        }
    }

    func isHidden(pid: Int32) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.isHidden ?? false
    }

    func activate(pid: Int32) {
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
        // Under macOS 14 cooperative activation the call above is only a request; setting
        // AXFrontmost works for trusted AX clients.
        AXUIElementSetAttributeValue(
            appElement(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if let frontmost = frontmostPID(), frontmost != pid {
            Log.debug("activating pid \(pid): frontmost is still pid \(frontmost)")
        }
    }

    func launch(_ spec: LaunchSpec, arguments: [String], workingDirectory: String?) throws {
        switch spec {
        case .command(let argv):
            guard let name = argv.first else { throw ToggleError("empty command") }
            let path = ProcessInfo.processInfo.environment["PATH"]
            let home = NSHomeDirectory()
            guard
                let executable = resolveExecutable(
                    name, path: path, home: home,
                    isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
            else {
                let dirs = executableSearchDirectories(path: path, home: home)
                throw ToggleError(
                    "command '\(name)' not found in: \(dirs.joined(separator: ", "))")
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(argv.dropFirst())
            if let workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            }
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                throw ToggleError("failed to run \(executable): \(error.localizedDescription)")
            }
        case .bundleID(let bundleID):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            else {
                throw ToggleError("no application with bundle id '\(bundleID)' is installed")
            }
            open(url, arguments: arguments)
        case .application(let path):
            guard FileManager.default.fileExists(atPath: path) else {
                throw ToggleError("application '\(path)' does not exist")
            }
            open(URL(fileURLWithPath: path), arguments: arguments)
        case .applicationName(let name):
            guard let url = applicationURL(named: name) else {
                throw ToggleError(
                    "no application named '\(name)' found in the Applications folders")
            }
            open(url, arguments: arguments)
        }
    }

    // MARK: - Helpers

    private func open(_ url: URL, arguments: [String]) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.arguments = arguments
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                Log.error("failed to open \(url.path): \(error.localizedDescription)")
            }
        }
    }

    private func applicationURL(named name: String) -> URL? {
        let fm = FileManager.default
        let roots = [
            "/Applications", "/Applications/Utilities", "/System/Applications",
            "/System/Applications/Utilities", "\(NSHomeDirectory())/Applications",
        ]
        for root in roots {
            let path = "\(root)/\(name).app"
            if fm.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private func identity(of app: NSRunningApplication) -> AppIdentity {
        AppIdentity(
            pid: app.processIdentifier,
            bundleID: app.bundleIdentifier ?? "",
            name: app.localizedName ?? "",
            executableName: app.executableURL?.lastPathComponent ?? "")
    }

    private func appElement(_ pid: Int32) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        // A hung app must not freeze the hotkey handler.
        AXUIElementSetMessagingTimeout(element, 1.0)
        return element
    }

    private func lookup(_ id: WindowID) -> (AXUIElement, AppIdentity)? {
        if let cached = cache[id] {
            // _AXUIElementGetWindow fails on an element whose window is gone.
            if windowID(cached.element) == id,
                NSRunningApplication(processIdentifier: cached.app.pid)?.isTerminated == false
            {
                return (cached.element, cached.app)
            }
            cache[id] = nil
        }
        var match: (AXUIElement, AppIdentity)?
        for app in runningApps() {
            guard let windows: [AXUIElement] = attribute(appElement(app.pid), kAXWindowsAttribute)
            else { continue }
            for window in windows {
                guard let windowID = windowID(window) else { continue }
                cache[windowID] = (window, app)
                if windowID == id, match == nil {
                    match = (window, app)
                }
            }
            if match != nil { break }
        }
        return match
    }

    private func require(_ id: WindowID) throws -> (AXUIElement, AppIdentity) {
        guard let found = lookup(id) else {
            throw ToggleError("window \(id) no longer exists")
        }
        return found
    }

    private func info(for element: AXUIElement, app: AppIdentity) -> WindowInfo? {
        guard let id = windowID(element) else { return nil }
        // Skip sheets, palettes, tooltips and other non-document windows.
        let subrole: String? = attribute(element, kAXSubroleAttribute)
        if let subrole, subrole != kAXStandardWindowSubrole as String,
            subrole != kAXDialogSubrole as String
        {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        if let value: AXValue = attribute(element, kAXPositionAttribute) {
            AXValueGetValue(value, .cgPoint, &position)
        }
        if let value: AXValue = attribute(element, kAXSizeAttribute) {
            AXValueGetValue(value, .cgSize, &size)
        }
        return WindowInfo(
            id: id,
            app: app,
            title: attribute(element, kAXTitleAttribute) ?? "",
            frame: Rect(
                x: Int(position.x.rounded()), y: Int(position.y.rounded()),
                width: Int(size.width.rounded()), height: Int(size.height.rounded())),
            isMinimized: attribute(element, kAXMinimizedAttribute) ?? false)
    }

    private func windowID(_ element: AXUIElement) -> WindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }

    private func set(
        _ element: AXUIElement, _ attribute: String, _ value: AXValue?, action: String
    ) throws {
        guard let value else { return }
        let result = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        if result != .success {
            throw AXFailure(action: action, code: result)
        }
    }
}
