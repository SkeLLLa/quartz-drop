import AppKit
import QuartzDropCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller: AppController
    private lazy var settings = SettingsWindowController(controller: controller)
    private var signalSources: [DispatchSourceSignal] = []
    private lazy var menuBar = MenuBarController(controller: controller) { [weak self] in
        self?.settings.show()
    }

    init(options: Options) {
        controller = AppController(options: options)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        var firstRun = false
        if !FileManager.default.fileExists(atPath: controller.configPath) {
            do {
                try writeExampleConfig(to: controller.configPath, force: false)
                Log.info("created example config at '\(controller.configPath)'")
                firstRun = true
            } catch {
                Log.error("failed to create example config: \(error.localizedDescription)")
            }
        }

        // Terminate through AppKit on Ctrl-C / `kill` / closing the terminal (SIGHUP) so windows
        // get their original frames back.
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }

        NSApp.mainMenu = makeMainMenu()

        controller.onMenuBarSettingChange = { [weak self] enabled in
            self?.updateMenuBar(enabled)
        }
        controller.start()
        updateMenuBar(controller.menuBarEnabled)

        if firstRun || controller.configError != nil
            || !controller.menuBarEnabled && !controller.isTrusted
        {
            settings.show()
        }
    }

    /// Launching the app again (Finder, Spotlight, `open -a`) opens Settings; this is the way in
    /// when the menu bar icon is disabled.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        settings.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    /// Accessory apps never show a menu bar, but key equivalents (Cmd-C, Cmd-W, ...) still route
    /// through `NSApp.mainMenu`.
    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        func add(_ title: String, to menu: NSMenu, _ action: Selector, _ key: String) {
            menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            item.submenu = menu
            mainMenu.addItem(item)
            return menu
        }

        let appMenu = submenu("QuartzDrop")
        add("Quit QuartzDrop", to: appMenu, #selector(NSApplication.terminate(_:)), "q")

        let edit = submenu("Edit")
        add("Cut", to: edit, #selector(NSText.cut(_:)), "x")
        add("Copy", to: edit, #selector(NSText.copy(_:)), "c")
        add("Paste", to: edit, #selector(NSText.paste(_:)), "v")
        add("Select All", to: edit, #selector(NSText.selectAll(_:)), "a")

        let window = submenu("Window")
        add("Close", to: window, #selector(NSWindow.performClose(_:)), "w")

        return mainMenu
    }

    private func updateMenuBar(_ enabled: Bool) {
        if enabled {
            menuBar.show()
        } else {
            menuBar.hide()
        }
    }
}
