import Foundation
import QuartzDropCore
import ServiceManagement

/// "Launch at login" through `SMAppService`, which only works for a bundled app.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var error: String?
    @Published private(set) var requiresApproval = false

    var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    init() {
        refresh()
    }

    func refresh() {
        let status = isAvailable ? SMAppService.mainApp.status : .notRegistered
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = "Failed to update login item: \(error.localizedDescription)"
            Log.error(self.error ?? "")
        }
        refresh()
    }
}
