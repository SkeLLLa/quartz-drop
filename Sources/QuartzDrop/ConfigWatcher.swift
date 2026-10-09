import Foundation
import QuartzDropCore

/// Watches the config file and calls back once per burst of changes.
///
/// The symlink-resolved file is watched directly, so in-place saves (truncate and rewrite) are
/// noticed. Its directory is watched too, so atomic saves that replace the file are noticed. When
/// the config path is a symlink, the link's own directory is also watched, so retargeting the link
/// is noticed. After each debounced burst, every source is reopened, because an atomic save or a
/// replaced directory leaves the old descriptors pointing at stale inodes. If the directory cannot
/// be opened (for example, it was deleted), the watcher retries every 2 seconds until it can.
/// The callback fires only when the file's (mtime, size, inode) signature changed.
@MainActor
final class ConfigWatcher {
    private struct Signature: Equatable {
        var device: Int64
        var inode: UInt64
        var size: Int64
        var seconds: Int
        var nanoseconds: Int
    }

    private let path: String
    private let onChange: () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    private var lastSignature: Signature?
    /// Bumped by `stop()` so retries scheduled before it are ignored.
    private var generation = 0
    private var warnedUnwatchable = false

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
        lastSignature = Self.signature(of: Self.resolve(path))
    }

    func start() {
        disarm()
        let target = Self.resolve(path)
        let directory = (target as NSString).deletingLastPathComponent
        guard let directorySource = makeSource(directory, mask: [.write, .rename, .delete]) else {
            if !warnedUnwatchable {
                warnedUnwatchable = true
                Log.warn(
                    "cannot watch config directory '\(directory)'; retrying every 2 seconds")
            }
            let scheduled = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == scheduled else { return }
                    self.start()
                    // The file may have appeared or changed while nothing was watching it.
                    if !self.sources.isEmpty { self.fireIfChanged() }
                }
            }
            return
        }
        warnedUnwatchable = false
        sources.append(directorySource)

        if let fileSource = makeSource(
            target, mask: [.write, .extend, .attrib, .delete, .rename, .link])
        {
            sources.append(fileSource)
        }

        let linkDirectory = (path as NSString).deletingLastPathComponent
        if linkDirectory != directory,
            let linkSource = makeSource(linkDirectory, mask: [.write, .rename, .delete])
        {
            sources.append(linkSource)
        }
    }

    func stop() {
        pending?.cancel()
        pending = nil
        disarm()
    }

    /// Records the file's current state as seen, so a change the app made itself (and already
    /// reloaded) does not trigger another callback.
    func markCurrent() {
        lastSignature = Self.signature(of: Self.resolve(path))
    }

    /// Cancels every source and any pending retry.
    private func disarm() {
        generation &+= 1
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
    }

    private func makeSource(
        _ path: String, mask: DispatchSource.FileSystemEvent
    ) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: mask, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.schedule() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pending = nil
                // Re-arm: symlinks may point elsewhere now, and the file or directory may be a
                // new inode after an atomic save or a directory replacement.
                self.start()
                self.fireIfChanged()
            }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func fireIfChanged() {
        let current = Self.signature(of: Self.resolve(path))
        guard current != lastSignature else { return }
        lastSignature = current
        onChange()
    }

    private static func resolve(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// The file's identity and contents stamp, or nil if it does not exist.
    private static func signature(of path: String) -> Signature? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return Signature(
            device: Int64(info.st_dev),
            inode: UInt64(info.st_ino),
            size: Int64(info.st_size),
            seconds: Int(info.st_mtimespec.tv_sec),
            nanoseconds: Int(info.st_mtimespec.tv_nsec))
    }
}
