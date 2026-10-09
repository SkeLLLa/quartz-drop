import AppKit
import ApplicationServices
import QuartzDropCore

/// Reports focus changes: app activation through NSWorkspace, and window focus changes inside
/// the tracked apps through AX observers.
@MainActor
final class FocusMonitor {
    private let onChange: () -> Void
    private var observers: [Int32: AXObserver] = [:]
    private var activationToken: NSObjectProtocol?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.notify() }
        }
    }

    /// Watches window focus inside exactly these processes.
    func watch(_ pids: Set<Int32>) {
        for (pid, observer) in observers where !pids.contains(pid) {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers[pid] = nil
        }
        for pid in pids where observers[pid] == nil {
            var observer: AXObserver?
            let callback: AXObserverCallback = { _, _, _, context in
                guard let context else { return }
                MainActor.assumeIsolated {
                    Unmanaged<FocusMonitor>.fromOpaque(context).takeUnretainedValue().notify()
                }
            }
            guard AXObserverCreate(pid, callback, &observer) == .success, let observer else {
                continue
            }
            let app = AXUIElementCreateApplication(pid)
            let context = Unmanaged.passUnretained(self).toOpaque()
            let result = AXObserverAddNotification(
                observer, app, kAXFocusedWindowChangedNotification as CFString, context)
            guard result == .success || result == .notificationAlreadyRegistered else {
                // Not stored, so the next watch() call (on every state change) retries.
                Log.debug("watching focus of pid \(pid) failed with AXError \(result.rawValue)")
                continue
            }
            CFRunLoopAddSource(
                CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers[pid] = observer
        }
    }

    private func notify() {
        // Let the window server settle so the focused window reflects the change.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated { self?.onChange() }
        }
    }
}
