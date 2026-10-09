import AppKit
import Combine
import QuartzDropCore

/// Optional status item listing the configured apps.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let controller: AppController
    private let openSettings: () -> Void
    private var item: NSStatusItem?

    init(controller: AppController, openSettings: @escaping () -> Void) {
        self.controller = controller
        self.openSettings = openSettings
    }

    func show() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.lefthalf.inset.filled",
            accessibilityDescription: "quartz-drop")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.item = item
    }

    func hide() {
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
    }

    // Rebuilt on every open so it always reflects the current config and permission state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !controller.isTrusted {
            let warning = NSMenuItem(
                title: "Grant Accessibility Access…", action: #selector(requestAccess),
                keyEquivalent: "")
            warning.target = self
            warning.image = NSImage(
                systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        if let error = controller.configError {
            let item = NSMenuItem(
                title: "Config error (see Settings)", action: nil, keyEquivalent: "")
            item.toolTip = error
            item.isEnabled = false
            menu.addItem(item)
        }

        if controller.rows.isEmpty {
            let empty = NSMenuItem(title: "No apps configured", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for row in controller.rows {
            let item = NSMenuItem(
                title: "\(row.name)\t\(row.hotkey)", action: #selector(toggleApp(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = row.name
            item.state = row.visible ? .on : .off
            if let error = row.error {
                item.image = NSImage(
                    systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
                item.toolTip = error
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        add(menu, "Settings…", #selector(settings), key: ",")
        add(menu, "Open Config", #selector(openConfig))
        add(menu, "Reload Config", #selector(reloadConfig), key: "r")
        menu.addItem(supportItem())
        add(menu, "Hide Menu Bar Icon", #selector(hideIcon))
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit quartz-drop", action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"))
    }

    /// "Support Ukraine" submenu.
    private func supportItem() -> NSMenuItem {
        let submenu = NSMenu()
        let note = NSMenuItem(
            title: "Instead of paying the author, consider:", action: nil, keyEquivalent: "")
        note.isEnabled = false
        submenu.addItem(note)
        for link in SupportLinks.all {
            let item = NSMenuItem(
                title: link.title, action: #selector(openLink(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = link.url
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: "Support Ukraine", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "heart", accessibilityDescription: nil)
        item.submenu = submenu
        return item
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func toggleApp(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        // Let the menu close and focus return before moving windows.
        DispatchQueue.main.async { [controller] in controller.toggle(name) }
    }

    @objc private func openLink(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func hideIcon() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Hide the menu bar icon?"
        alert.informativeText =
            "Hotkeys keep working. To show the icon again, open QuartzDrop again to get to Settings, or set menu_bar = true in the config."
        alert.addButton(withTitle: "Hide")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            controller.setMenuBar(false)
        }
    }

    @objc private func requestAccess() { controller.requestAccessibility() }
    @objc private func settings() { openSettings() }
    @objc private func openConfig() { controller.openConfig() }
    @objc private func reloadConfig() { controller.reload() }
}
