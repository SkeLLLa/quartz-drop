import Testing

@testable import QuartzDropCore

@Suite struct MatchingTests {
    let safari = AppIdentity(
        pid: 10, bundleID: "com.apple.Safari", name: "Safari", executableName: "Safari")
    let kitty = AppIdentity(pid: 11, bundleID: "", name: "kitty", executableName: "kitty")

    func config(
        bundleID: String? = nil, filename: String? = nil, process: String? = nil,
        title: String? = nil
    ) throws -> AppConfig {
        AppConfig(
            name: "t", hotkey: try Hotkey.parse("ctrl+a"), bundleID: bundleID, filename: filename,
            processName: try process.map { try Pattern($0) },
            windowTitle: try title.map { try Pattern($0) })
    }

    func window(_ id: WindowID, _ app: AppIdentity, title: String = "w", minimized: Bool = false)
        -> WindowInfo
    {
        WindowInfo(
            id: id, app: app, title: title, frame: Rect(x: 0, y: 0, width: 10, height: 10),
            isMinimized: minimized)
    }

    @Test func bundleIDIsCaseInsensitive() throws {
        let c = try config(bundleID: "COM.APPLE.SAFARI")
        #expect(c.matchesApp(safari))
        #expect(!c.matchesApp(kitty))
    }

    @Test func processNameMatchesAnyIdentityField() throws {
        #expect(try config(process: "^com\\.apple\\.safari$").matchesApp(safari))
        #expect(try config(process: "^safari$").matchesApp(safari))
        let exec = AppIdentity(
            pid: 1, bundleID: "x.y", name: "Pretty Name", executableName: "prettyd")
        #expect(try config(process: "^prettyd$").matchesApp(exec))
        #expect(try !config(process: "^nothing$").matchesApp(exec))
    }

    @Test func processNameIgnoresEmptyFields() throws {
        // An empty bundle ID must not satisfy a pattern like ".*" by itself being matched.
        let bare = AppIdentity(pid: 1, bundleID: "", name: "", executableName: "")
        #expect(try !config(process: ".*").matchesApp(bare))
    }

    @Test func bundleIDAndProcessNameBothApply() throws {
        let c = try config(bundleID: "com.apple.Safari", process: "^kitty$")
        #expect(!c.matchesApp(safari))
    }

    @Test func filenameBasenameMatch() throws {
        let c = try config(filename: "/Applications/Safari.app")
        #expect(c.matchesApp(safari))
        #expect(!c.matchesApp(kitty))
        #expect(try config(filename: "Safari.app").matchesApp(safari))
        #expect(try config(filename: "/usr/local/bin/KITTY").matchesApp(kitty))
        let preview = AppIdentity(
            pid: 2, bundleID: "x", name: "Safari Technology Preview", executableName: "STP")
        #expect(!c.matchesApp(preview))
    }

    @Test func filenameIgnoredWhenWindowTitleSet() throws {
        let c = try config(filename: "Nothing", title: "foo")
        #expect(c.matchesApp(safari))
    }

    @Test func windowTitleFilter() throws {
        let c = try config(bundleID: "com.apple.Safari", title: "^inbox")
        #expect(c.matches(window(1, safari, title: "Inbox (3)")))
        #expect(!c.matches(window(2, safari, title: "Sent")))
        #expect(!c.matches(window(3, kitty, title: "Inbox")))
    }

    @Test func windowTitleOnlyMatchesAnyApp() throws {
        let c = try config(title: "scratch")
        #expect(c.matches(window(1, kitty, title: "my Scratch pad")))
        #expect(c.matches(window(2, safari, title: "scratch")))
    }

    @Test func findBestMatchPrefersNonMinimized() throws {
        let c = try config(bundleID: "com.apple.Safari")
        let windows = [
            window(1, safari, minimized: true), window(2, safari), window(3, safari),
            window(4, kitty),
        ]
        let (best, count) = findBestMatch(windows, for: c)
        #expect(best?.id == 2)
        #expect(count == 3)
    }

    @Test func findBestMatchFallsBackToMinimized() throws {
        let c = try config(bundleID: "com.apple.Safari")
        let (best, count) = findBestMatch([window(1, safari, minimized: true)], for: c)
        #expect(best?.id == 1)
        #expect(count == 1)
    }

    @Test func findBestMatchNone() throws {
        let c = try config(bundleID: "com.apple.Safari")
        let (best, count) = findBestMatch([window(1, kitty)], for: c)
        #expect(best == nil)
        #expect(count == 0)
        let (none, zero) = findBestMatch([], for: c)
        #expect(none == nil && zero == 0)
    }
}
