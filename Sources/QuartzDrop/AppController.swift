import AppKit
import ApplicationServices
import QuartzDropCore

/// Owns the config, the toggle service, and the system integrations; the menu bar and the
/// settings window observe it.
@MainActor
final class AppController: ObservableObject {
    struct AppRow: Identifiable {
        var id: String { name }
        let name: String
        let hotkey: String
        let target: String
        let placement: String
        let hideBehavior: String
        let visible: Bool
        let error: String?
    }

    let configPath: String
    @Published private(set) var config: Config?
    @Published private(set) var configError: String?
    @Published private(set) var warnings: [String] = []
    @Published private(set) var rows: [AppRow] = []
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var lastLoaded: Date?

    /// Called when `menu_bar` changes after a reload.
    var onMenuBarSettingChange: ((Bool) -> Void)?

    private let options: Options
    private let windowManager = AXWindowManager()
    private lazy var toggleService = ToggleService(apps: [], windowManager: windowManager)
    private lazy var hotkeys = HotkeyCenter { [weak self] name in self?.hotkeyPressed(name) }
    private lazy var focusMonitor = FocusMonitor { [weak self] in self?.focusChanged() }
    private var watcher: ConfigWatcher?
    private var trustTimer: Timer?
    private var terminationObserver: NSObjectProtocol?

    init(options: Options) {
        self.options = options
        configPath = options.resolvedConfigPath
    }

    var menuBarEnabled: Bool { config?.menuBar ?? true }

    func start() {
        toggleService.onStateChange = { [weak self] in self?.stateChanged() }
        _ = focusMonitor
        reload()
        watcher = ConfigWatcher(path: configPath) { [weak self] in
            Log.info("config file changed; reloading")
            self?.reload()
        }
        watcher?.start()
        if !isTrusted {
            Log.warn("Accessibility access is not granted; windows cannot be moved until it is")
            requestAccessibility()
        }
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { self?.toggleService.handleAppTerminated(pid: pid) }
        }
    }

    func shutdown() {
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
        toggleService.restoreTrackedWindows()
        hotkeys.unregisterAll()
        watcher?.stop()
    }

    /// Re-reads the config. An invalid config keeps the previous apps active.
    func reload() {
        let previousMenuBar = menuBarEnabled
        do {
            let loaded = try Config.load(path: configPath)
            config = loaded
            configError = nil
            warnings = loaded.warnings
            Log.level = options.effectiveLogLevel(config: loaded.logLevel)
            for warning in loaded.warnings {
                Log.warn(warning)
            }
            for option in loaded.ignored {
                Log.info("ignored on macOS: \(option)")
            }
            toggleService.replaceApps(loaded.apps)
            warnings += hotkeys.register(loaded.apps)
            lastLoaded = Date()
            watcher?.markCurrent()
            Log.info("loaded \(loaded.apps.count) apps from '\(configPath)'")
        } catch {
            configError = error.localizedDescription
            Log.error(error.localizedDescription)
        }
        stateChanged()
        if previousMenuBar != menuBarEnabled {
            onMenuBarSettingChange?(menuBarEnabled)
        }
    }

    func toggle(_ name: String, hideIfVisible: Bool = false) {
        if !AXIsProcessTrusted() {
            Log.error("toggle for '\(name)' ignored: Accessibility access is not granted")
            requestAccessibility()
            return
        }
        Task { await toggleService.handleHotkey(name, hideIfVisible: hideIfVisible) }
    }

    /// Writes `menu_bar` to the config file and reloads immediately.
    func setMenuBar(_ shown: Bool) {
        do {
            let text = try String(contentsOfFile: configPath, encoding: .utf8)
            try ConfigEditor.setTopLevel("menu_bar", to: shown, in: text)
                .write(toFile: configPath, atomically: false, encoding: .utf8)
            Log.info("set menu_bar = \(shown) in '\(configPath)'")
            reload()
        } catch {
            configError = "failed to update menu_bar: \(error.localizedDescription)"
            Log.error(configError ?? "")
        }
    }

    func openConfig() {
        NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
    }

    func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: configPath)])
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        if !isTrusted {
            startTrustPolling()
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Private

    private func hotkeyPressed(_ name: String) {
        toggle(name)
    }

    private func focusChanged() {
        toggleService.handleFocusChange()
    }

    private func stateChanged() {
        focusMonitor.watch(toggleService.trackedPIDs)
        rows = toggleService.order.compactMap { name in
            guard let app = toggleService.apps[name] else { return nil }
            let config = app.config
            let placement = config.placement
            return AppRow(
                name: name,
                hotkey: config.hotkey.display,
                target: config.bundleID ?? config.filename ?? config.processName?.source
                    ?? config.windowTitle?.source ?? "",
                placement:
                    "\(placement.width) × \(placement.height), \(placement.position.rawValue)",
                hideBehavior: config.hideBehavior.rawValue,
                visible: toggleService.isVisible(name),
                error: app.lastError)
        }
    }

    private func startTrustPolling() {
        guard trustTimer == nil else { return }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollTrust() }
        }
    }

    private func pollTrust() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            isTrusted = trusted
            if trusted {
                Log.info("Accessibility access granted")
            }
        }
        if trusted {
            trustTimer?.invalidate()
            trustTimer = nil
        }
    }
}
