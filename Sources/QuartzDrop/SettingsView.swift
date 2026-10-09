import AppKit
import QuartzDropCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var loginItem: LoginItem

    var body: some View {
        TabView {
            GeneralTab(controller: controller, loginItem: loginItem)
                .tabItem { Label("General", systemImage: "gearshape") }
            AppsTab(controller: controller)
                .tabItem { Label("Apps", systemImage: "rectangle.stack") }
            PermissionsTab(controller: controller)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .padding()
        .frame(minWidth: 620, minHeight: 400)
    }
}

private struct GeneralTab: View {
    @ObservedObject var controller: AppController
    @ObservedObject var loginItem: LoginItem

    var body: some View {
        Form {
            Section("Configuration") {
                LabeledContent("File") {
                    Text(controller.configPath)
                        .textSelection(.enabled)
                        .font(.system(.body, design: .monospaced))
                }
                HStack {
                    Button("Open") { controller.openConfig() }
                    Button("Reveal in Finder") { controller.revealConfig() }
                    Button("Reload") { controller.reload() }
                    Spacer()
                    if let loaded = controller.lastLoaded {
                        Text("Loaded \(loaded.formatted(date: .omitted, time: .standard))")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = controller.configError {
                    Label(error, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                ForEach(controller.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if !(controller.config?.ignored ?? []).isEmpty {
                    DisclosureGroup("Ignored on macOS (\(controller.config?.ignored.count ?? 0))") {
                        ForEach(controller.config?.ignored ?? [], id: \.self) { option in
                            Text(option).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            Section("Startup") {
                Toggle(
                    "Launch at login",
                    isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })
                )
                .disabled(!loginItem.isAvailable)
                if !loginItem.isAvailable {
                    Text("Available when running from QuartzDrop.app.")
                        .foregroundStyle(.secondary)
                }
                if loginItem.requiresApproval {
                    HStack {
                        Text("Allow QuartzDrop in System Settings → General → Login Items")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open System Settings") { loginItem.openSystemSettings() }
                    }
                }
                if let error = loginItem.error {
                    Text(error).foregroundStyle(.red)
                }
            }
            Section {
                Toggle(
                    "Show menu bar icon",
                    isOn: Binding(
                        get: { controller.menuBarEnabled }, set: { controller.setMenuBar($0) }))
            } header: {
                Text("Menu Bar")
            } footer: {
                Text(
                    "Saved as menu_bar in the config file. With the icon hidden, open QuartzDrop again to get back to Settings."
                )
                .foregroundStyle(.secondary)
            }
            Section("Support Ukraine") {
                Text(SupportLinks.note)
                    .foregroundStyle(.secondary)
                HStack {
                    ForEach(SupportLinks.all) { link in
                        Link(link.title, destination: link.url)
                    }
                }
            }
            Section {
                LabeledContent("Version", value: About.versionLine)
                if let buildDate = About.buildDate {
                    LabeledContent("Built", value: buildDate)
                }
                HStack {
                    Link("Source code", destination: About.repository)
                    Spacer()
                    Button("About quartz-drop…") { About.show() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppsTab: View {
    @ObservedObject var controller: AppController

    var body: some View {
        VStack(alignment: .leading) {
            Table(controller.rows) {
                TableColumn("Name") { row in
                    HStack {
                        Circle()
                            .fill(row.visible ? Color.green : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                        Text(row.name)
                        if let error = row.error {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .help(error)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                                .help(error)
                        }
                    }
                }
                TableColumn("Hotkey", value: \.hotkey)
                TableColumn("Matches", value: \.target)
                TableColumn("Placement", value: \.placement)
                TableColumn("Hide", value: \.hideBehavior)
                TableColumn("") { row in
                    Button(row.visible ? "Hide" : "Show") {
                        controller.toggle(row.name, hideIfVisible: true)
                    }
                }
                .width(70)
            }
            Text("Edit the config file to add or change apps; it reloads automatically.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct PermissionsTab: View {
    @ObservedObject var controller: AppController

    var body: some View {
        Form {
            Section("Accessibility") {
                if controller.isTrusted {
                    Label("Access granted", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Label(
                        "quartz-drop needs Accessibility access to move, focus, and minimize windows of other apps.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    HStack {
                        Button("Request Access") { controller.requestAccessibility() }
                        Button("Open Privacy Settings") { controller.openAccessibilitySettings() }
                    }
                    Text(
                        "macOS ties the permission to the app's code signature. After installing an unsigned or ad-hoc signed build, remove quartz-drop from the list and add it again."
                    )
                    .foregroundStyle(.secondary)
                }
            }
            Section("Hotkeys") {
                Text("Global hotkeys need no extra permission.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Hosts `SettingsView` in a regular window; the app has no main menu or Dock icon.
@MainActor
final class SettingsWindowController {
    private let controller: AppController
    private let loginItem = LoginItem()
    private var window: NSWindow?

    init(controller: AppController) {
        self.controller = controller
    }

    func show() {
        loginItem.refresh()
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "quartz-drop Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: SettingsView(controller: controller, loginItem: loginItem))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
