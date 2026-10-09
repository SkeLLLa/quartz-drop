import Foundation

/// The window-system operations the toggle logic needs. The app implements it with the macOS
/// Accessibility API; tests use an in-memory fake.
@MainActor
public protocol WindowManaging: AnyObject {
    func runningApps() -> [AppIdentity]
    func windows(of app: AppIdentity) -> [WindowInfo]
    func window(id: WindowID) -> WindowInfo?
    func activeWindow() -> WindowInfo?
    func frontmostPID() -> Int32?
    func cursorPosition() -> Point?
    func screens() -> [ScreenInfo]
    func setFrame(_ frame: Rect, of window: WindowID) throws
    func focus(_ window: WindowID) throws
    func setMinimized(_ minimized: Bool, window: WindowID) throws
    func setHidden(_ hidden: Bool, pid: Int32)
    func isHidden(pid: Int32) -> Bool
    func activate(pid: Int32)
    /// `arguments` apply to app bundles; a `.command` argv already contains them.
    func launch(_ spec: LaunchSpec, arguments: [String], workingDirectory: String?) throws
}

public struct ToggleError: Error, LocalizedError, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
    public var errorDescription: String? { message }
}

public struct ManagedApp: Sendable {
    public var config: AppConfig
    public var trackedWindowID: WindowID?
    public var trackedPID: Int32?
    /// Window frame from before quartz-drop first placed it; restored on quit.
    public var restoreFrame: Rect?
    /// Window that `restoreFrame` belongs to. Kept when tracking is lost, so a window that is
    /// found again is not re-recorded at the frame quartz-drop gave it.
    public var restoreWindowID: WindowID?
    /// Description of the last failed toggle; cleared by the next successful one.
    public var lastError: String?
    /// App that was frontmost before this one was shown; focus returns there when hiding.
    public var previousFrontmostPID: Int32?

    public init(config: AppConfig) {
        self.config = config
    }
}

public struct ToggleTiming: Sendable {
    public var hotkeyDebounce: Duration
    public var spawnPollInterval: Duration
    public var spawnPollAttempts: Int

    public init(
        hotkeyDebounce: Duration = .milliseconds(150),
        spawnPollInterval: Duration = .milliseconds(250),
        spawnPollAttempts: Int = 80
    ) {
        self.hotkeyDebounce = hotkeyDebounce
        self.spawnPollInterval = spawnPollInterval
        self.spawnPollAttempts = spawnPollAttempts
    }
}

/// Shows and hides the configured apps. At most one managed app is visible at a time; showing
/// one hides the other, like plasma-drop.
@MainActor
public final class ToggleService {
    public private(set) var apps: [String: ManagedApp] = [:]
    public private(set) var order: [String] = []
    public private(set) var visibleAppName: String?
    /// Called after every state change so UI and focus observers can refresh.
    public var onStateChange: (() -> Void)?

    private let wm: WindowManaging
    private let timing: ToggleTiming
    private let now: () -> ContinuousClock.Instant
    private let sleep: (Duration) async throws -> Void
    private var recentHotkeys: [String: ContinuousClock.Instant] = [:]
    private var pendingSpawns: Set<String> = []
    /// Toggles queued or running. Focus changes are ignored while any is in flight.
    private var togglesInFlight = 0
    /// Last toggle in the queue; each toggle waits for the previous one to finish.
    private var queueTail: Task<Void, Never>?

    public init(
        apps configs: [AppConfig],
        windowManager: WindowManaging,
        timing: ToggleTiming = ToggleTiming(),
        now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now },
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        wm = windowManager
        self.timing = timing
        self.now = now
        self.sleep = sleep
        replaceApps(configs)
    }

    /// Processes of windows quartz-drop currently tracks; focus observers watch these.
    public var trackedPIDs: Set<Int32> {
        Set(apps.values.compactMap(\.trackedPID))
    }

    public func isVisible(_ name: String) -> Bool {
        visibleAppName == name
    }

    /// Hotkey entry point: drops key repeats inside the debounce window and logs failures.
    /// A failure is also stored in the app's `lastError` for the UI.
    public func handleHotkey(_ name: String, hideIfVisible: Bool = false) async {
        let instant = now()
        recentHotkeys = recentHotkeys.filter { instant - $0.value <= timing.hotkeyDebounce }
        if recentHotkeys[name] != nil {
            Log.info("ignored repeated hotkey for '\(name)'")
            return
        }
        recentHotkeys[name] = instant

        do {
            try await toggle(name, hideIfVisible: hideIfVisible)
        } catch {
            Log.error("failed to toggle '\(name)': \(error)")
            apps[name]?.lastError = String(describing: error)
            onStateChange?()
        }
    }

    /// Shows the app, or hides it when it is visible and focused (or `hideIfVisible` is set).
    ///
    /// Toggles run one at a time in call order: a toggle waits for earlier ones, including an
    /// app start that is still waiting for its window, so two apps never end up visible.
    public func toggle(_ name: String, hideIfVisible: Bool = false) async throws {
        guard apps[name] != nil else {
            throw ToggleError("unknown app '\(name)'")
        }
        if pendingSpawns.contains(name) {
            Log.info("start of '\(name)' already in progress; waiting for its window")
            return
        }

        togglesInFlight += 1
        defer { togglesInFlight -= 1 }

        let previous = queueTail
        let work = Task { @MainActor in
            await previous?.value
            try await self.performToggle(name, hideIfVisible: hideIfVisible)
        }
        queueTail = Task { _ = await work.result }
        try await work.value
    }

    private func performToggle(_ name: String, hideIfVisible: Bool) async throws {
        defer { onStateChange?() }
        // The app may have been removed by a reload while this toggle was queued.
        guard let app = apps[name] else {
            throw ToggleError("unknown app '\(name)'")
        }
        try await toggleNow(name, app, hideIfVisible: hideIfVisible)
        apps[name]?.lastError = nil
    }

    private func toggleNow(_ name: String, _ app: ManagedApp, hideIfVisible: Bool) async throws {
        if isVisible(name) {
            if let window = resolveExisting(app) {
                track(name, window)
                if hideIfVisible || isFocused(window) {
                    try hide(name)
                    return
                }
                Log.debug("'\(name)' is visible but not focused; bringing it forward")
            } else {
                apps[name]?.trackedWindowID = nil
                apps[name]?.trackedPID = nil
                setVisible(name, false)
            }
        }

        // Pick the screen and the focus to return to before hiding another app moves focus.
        let screen = try currentScreen(for: app.config)
        var previousFrontmost = wm.frontmostPID()
        if let other = visibleAppName, other != name {
            if let otherApp = apps[other], otherApp.trackedPID == previousFrontmost {
                previousFrontmost = otherApp.previousFrontmostPID
            }
            do {
                try hide(other, restoreFocus: false)
            } catch {
                Log.warn("failed to hide '\(other)' before showing '\(name)': \(error)")
            }
        }

        try await show(name, on: screen, previousFrontmost: previousFrontmost)
    }

    /// Hides the visible app when `hide_on_focus_lost` is set and another window became active.
    public func handleFocusChange() {
        guard togglesInFlight == 0,
            let name = visibleAppName, let app = apps[name], app.config.hideOnFocusLost,
            let tracked = app.trackedWindowID
        else {
            return
        }
        // Re-read the focus: the notification may be stale by the time it is handled.
        if wm.activeWindow()?.id == tracked {
            return
        }
        // Another window of the same app is focused. Hiding the process would hide that window
        // too, so leave it; minimize and offscreen affect only the tracked window.
        if app.config.hideBehavior == .hide, let pid = app.trackedPID, wm.frontmostPID() == pid {
            return
        }
        do {
            try hide(name, restoreFocus: false)
            Log.info("hid app '\(name)' after focus moved away")
        } catch {
            Log.error("failed to hide '\(name)' after focus loss: \(error)")
        }
        onStateChange?()
    }

    /// Applies a reloaded config, keeping tracked windows for apps whose name and matching
    /// criteria did not change. Windows of removed apps, and of apps whose matchers changed, are
    /// restored and released.
    public func replaceApps(_ configs: [AppConfig]) {
        let names = Set(configs.map(\.name))
        for (name, app) in apps where !names.contains(name) {
            restore(app)
        }

        var updated: [String: ManagedApp] = [:]
        for config in configs {
            var app = apps[config.name] ?? ManagedApp(config: config)
            if apps[config.name] != nil, !app.config.hasSameMatchers(as: config) {
                Log.info("matching for app '\(config.name)' changed; releasing its window")
                restore(app)
                app.trackedWindowID = nil
                app.trackedPID = nil
                app.restoreFrame = nil
                app.restoreWindowID = nil
                app.previousFrontmostPID = nil
                if visibleAppName == config.name {
                    visibleAppName = nil
                }
            }
            app.config = config
            updated[config.name] = app
        }
        apps = updated
        order = configs.map(\.name)
        if let visible = visibleAppName, !names.contains(visible) {
            visibleAppName = nil
        }
        onStateChange?()
    }

    /// Forgets windows of a process that quit.
    public func handleAppTerminated(pid: Int32) {
        var changed = false
        for name in order {
            guard var app = apps[name] else { continue }
            if app.trackedPID == pid {
                app.trackedWindowID = nil
                app.trackedPID = nil
                app.restoreFrame = nil
                app.restoreWindowID = nil
                if visibleAppName == name {
                    visibleAppName = nil
                }
                changed = true
                Log.info("app '\(name)' quit; released its window")
            }
            if app.previousFrontmostPID == pid {
                app.previousFrontmostPID = nil
                changed = true
            }
            apps[name] = app
        }
        if changed {
            onStateChange?()
        }
    }

    /// Puts every tracked window back where it was before quartz-drop moved it, and un-parks
    /// windows of apps that are not visible.
    public func restoreTrackedWindows() {
        for name in order {
            if let app = apps[name] {
                restore(app)
            }
        }
    }

    // MARK: - Show / hide

    private func show(_ name: String, on screen: ScreenInfo, previousFrontmost: Int32?)
        async throws
    {
        guard let config = apps[name]?.config else { return }
        do {
            try screen.validatePlacement(config.placement)
        } catch let error as ConfigError {
            throw ToggleError("invalid placement for '\(name)': \(error.message)")
        }

        let window = try await resolveWindow(name, config: config)
        guard var app = apps[name] else { return }

        if wm.isHidden(pid: window.app.pid) {
            wm.setHidden(false, pid: window.app.pid)
        }
        if window.isMinimized {
            try wm.setMinimized(false, window: window.id)
        }

        if app.restoreWindowID != window.id || app.restoreFrame == nil {
            app.restoreWindowID = window.id
            if window.frame == offscreenRect(for: window.frame, screens: wm.screens()) {
                // Likely left parked by an earlier run; restoring there would lose the window.
                Log.info(
                    "app '\(name)' window looks parked off screen; not recording its frame for restore"
                )
                app.restoreFrame = nil
            } else {
                app.restoreFrame = window.frame
            }
        }
        app.trackedWindowID = window.id
        app.trackedPID = window.app.pid
        if previousFrontmost != window.app.pid {
            app.previousFrontmostPID = previousFrontmost
        }
        apps[name] = app

        let target = screen.placementRect(config.placement)
        // The window is found, so mark it visible even if placing or focusing fails; otherwise
        // every press would retry the show instead of hiding.
        do {
            try wm.setFrame(target, of: window.id)
        } catch {
            Log.warn("could not place app '\(name)': \(error)")
        }
        do {
            try wm.focus(window.id)
        } catch {
            Log.warn("could not focus app '\(name)': \(error)")
        }

        if let actual = wm.window(id: window.id)?.frame, actual != target {
            Log.info(
                "app '\(name)' window is \(actual) instead of \(target); the app may enforce a minimum size or resize in steps"
            )
        }
        setVisible(name, true)
        Log.info("showed app '\(name)' on '\(screen.name)'")
    }

    private func hide(_ name: String, restoreFocus: Bool = true) throws {
        guard let app = apps[name] else { return }
        guard let window = resolveExisting(app) else {
            Log.warn("cannot hide app '\(name)' because no tracked window is attached")
            setVisible(name, false)
            return
        }
        track(name, window)

        let wasFrontmost = wm.frontmostPID() == window.app.pid
        switch app.config.hideBehavior {
        case .hide:
            wm.setHidden(true, pid: window.app.pid)
        case .minimize:
            try wm.setMinimized(true, window: window.id)
        case .offscreen:
            try wm.setFrame(offscreenRect(for: window.frame, screens: wm.screens()), of: window.id)
        }

        // Hiding an app already hands focus to the next app; minimize and offscreen keep the
        // parked app frontmost, so hand focus back explicitly.
        if restoreFocus, wasFrontmost, app.config.hideBehavior != .hide,
            let previous = app.previousFrontmostPID, previous != window.app.pid
        {
            wm.activate(pid: previous)
        }

        setVisible(name, false)
        Log.info("hid app '\(name)'")
    }

    private func restore(_ app: ManagedApp) {
        guard let id = app.restoreWindowID ?? app.trackedWindowID, let window = wm.window(id: id)
        else {
            return
        }
        // A parked window would stay hidden or minimized after quartz-drop lets go of it.
        if !isVisible(app.config.name) {
            if wm.isHidden(pid: window.app.pid) {
                wm.setHidden(false, pid: window.app.pid)
            }
            if window.isMinimized {
                try? wm.setMinimized(false, window: id)
            }
        }
        guard let frame = app.restoreFrame else { return }
        do {
            try wm.setFrame(frame, of: id)
            Log.info("restored app '\(app.config.name)' window to \(frame)")
        } catch {
            Log.warn("failed to restore app '\(app.config.name)' window: \(error)")
        }
    }

    // MARK: - Window resolution

    private func resolveWindow(_ name: String, config: AppConfig) async throws -> WindowInfo {
        if let app = apps[name], let window = resolveExisting(app) {
            return window
        }
        guard config.attachMode == .findOrStart, let spec = config.launch else {
            throw ToggleError("no existing window matched app '\(name)'")
        }

        pendingSpawns.insert(name)
        defer { pendingSpawns.remove(name) }

        let running = config.hasAppIdentity ? wm.runningApps().first(where: config.matchesApp) : nil
        if let running, case .command = spec {
            // Running a bare command again could start a second instance. Activating the app
            // makes macOS switch to the desktop holding its window, where AX can see it.
            Log.info("app '\(name)' is running without a visible window; activating it")
            wm.activate(pid: running.pid)
        } else {
            // Opening an already running .app sends it a reopen event, which makes most apps
            // create a window instead of starting a second instance.
            try wm.launch(
                spec, arguments: config.arguments, workingDirectory: config.workingDirectory)
            Log.info("started app '\(name)'")
        }

        for _ in 0..<timing.spawnPollAttempts {
            try await sleep(timing.spawnPollInterval)
            if let window = findMatchingWindow(config) {
                return window
            }
        }
        throw ToggleError("started app '\(name)' but no matching window appeared")
    }

    private func resolveExisting(_ app: ManagedApp) -> WindowInfo? {
        // Window IDs are only unique per session, so check the window still belongs to a
        // matching app. The title is not rechecked: titles change while a window is in use.
        if let id = app.trackedWindowID, let window = wm.window(id: id),
            app.config.matchesApp(window.app)
        {
            return window
        }
        return findMatchingWindow(app.config)
    }

    /// Prefers windows no other managed app tracks, so two apps with overlapping matchers do
    /// not fight over one window.
    private func findMatchingWindow(_ config: AppConfig) -> WindowInfo? {
        let windows = wm.runningApps().filter(config.matchesApp).flatMap(wm.windows(of:))
        let claimed = Set(
            apps.values.filter { $0.config.name != config.name }.compactMap(\.trackedWindowID))
        var (best, count) = findBestMatch(windows.filter { !claimed.contains($0.id) }, for: config)
        if best == nil {
            (best, count) = findBestMatch(windows, for: config)
        }
        if count > 1 {
            Log.debug("\(count) windows matched app '\(config.name)'; using '\(best?.title ?? "")'")
        }
        return best
    }

    private func isFocused(_ window: WindowInfo) -> Bool {
        !window.isMinimized && !wm.isHidden(pid: window.app.pid)
            && wm.activeWindow()?.id == window.id
    }

    private func track(_ name: String, _ window: WindowInfo) {
        apps[name]?.trackedWindowID = window.id
        apps[name]?.trackedPID = window.app.pid
    }

    private func setVisible(_ name: String, _ visible: Bool) {
        if visible {
            visibleAppName = name
        } else if visibleAppName == name {
            visibleAppName = nil
        }
    }

    /// Returns the configured screen when connected, otherwise the screen under the cursor, then
    /// the screen of the active window.
    private func currentScreen(for config: AppConfig) throws -> ScreenInfo {
        let screens = wm.screens()
        guard let first = screens.first else {
            throw ToggleError("no screens available")
        }
        if let name = config.placement.screen {
            if let screen = screens.first(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }) {
                return screen
            }
            Log.warn(
                "screen '\(name)' configured for app '\(config.name)' was not found; using the screen under the cursor"
            )
        }
        if let cursor = wm.cursorPosition(),
            let screen = screens.first(where: { $0.frame.contains(cursor) })
        {
            return screen
        }
        if let active = wm.activeWindow() {
            return screens.max {
                $0.frame.overlapArea(with: active.frame) < $1.frame.overlapArea(with: active.frame)
            } ?? first
        }
        return first
    }
}

extension AppConfig {
    /// Whether the config narrows matching to specific applications rather than any window
    /// with a matching title.
    var hasAppIdentity: Bool {
        bundleID != nil || processName != nil || (windowTitle == nil && filename != nil)
    }

    /// Whether `other` selects and launches the same windows, so a tracked window stays valid.
    func hasSameMatchers(as other: AppConfig) -> Bool {
        bundleID == other.bundleID && filename == other.filename
            && processName?.source == other.processName?.source
            && windowTitle?.source == other.windowTitle?.source && launch == other.launch
    }
}
