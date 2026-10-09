import Carbon
import QuartzDropCore

/// Registers global hotkeys with Carbon `RegisterEventHotKey`, which needs no extra permission.
@MainActor
final class HotkeyCenter {
    private static let signature: OSType = 0x5144_7270  // "QDrp"

    private var refs: [EventHotKeyRef] = []
    private var names: [UInt32: String] = [:]
    private var handler: EventHandlerRef?
    private let onPress: (String) -> Void

    init(onPress: @escaping (String) -> Void) {
        self.onPress = onPress
    }

    /// Replaces all registrations and returns a message per hotkey that could not be registered.
    func register(_ apps: [AppConfig]) -> [String] {
        unregisterAll()
        installHandler()

        var failures: [String] = []
        for (index, app) in apps.enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                app.hotkey.keyCode, app.hotkey.modifiers.rawValue,
                EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0,
                &ref)
            if status == noErr, let ref {
                refs.append(ref)
                names[id] = app.name
                Log.info("registered hotkey \(app.hotkey.display) for app '\(app.name)'")
            } else {
                let message =
                    "failed to register hotkey '\(app.hotkey.raw)' for app '\(app.name)' (OSStatus \(status)); another app may already use it"
                Log.error(message)
                failures.append(message)
            }
        }
        return failures
    }

    func unregisterAll() {
        for ref in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        names.removeAll()
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard status == noErr else { return status }
                // Carbon delivers application-target events on the main thread.
                MainActor.assumeIsolated {
                    let center = Unmanaged<HotkeyCenter>.fromOpaque(context).takeUnretainedValue()
                    center.fire(id)
                }
                return noErr
            }, 1, &spec, context, &handler)
    }

    private func fire(_ id: EventHotKeyID) {
        guard id.signature == Self.signature, let name = names[id.id] else { return }
        onPress(name)
    }
}
