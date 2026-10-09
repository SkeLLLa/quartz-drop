import Foundation
import Testing

@testable import QuartzDropCore

@MainActor
final class FakeWindowManager: WindowManaging {
    var apps: [AppIdentity] = []
    var windowsByID: [WindowID: WindowInfo] = [:]
    var activeWindowID: WindowID?
    var frontmost: Int32?
    var hiddenPIDs: Set<Int32> = []
    var cursor: Point?
    var screenList: [ScreenInfo] = []

    var failSetFrame = false
    var failFocus = false

    var launches: [(spec: LaunchSpec, workingDirectory: String?)] = []
    var setFrameCalls: [(frame: Rect, window: WindowID)] = []
    var activated: [Int32] = []

    /// After `launch`, the Nth `runningApps()` call makes this app and window appear.
    var spawnAfterPolls: Int?
    var spawn: (app: AppIdentity, window: WindowInfo)?
    private var pollsSinceLaunch: Int?

    func runningApps() -> [AppIdentity] {
        if let polls = pollsSinceLaunch {
            pollsSinceLaunch = polls + 1
            if let after = spawnAfterPolls, polls + 1 >= after, let spawn {
                if !apps.contains(spawn.app) { apps.append(spawn.app) }
                windowsByID[spawn.window.id] = spawn.window
            }
        }
        return apps
    }

    func windows(of app: AppIdentity) -> [WindowInfo] {
        windowsByID.values.filter { $0.app.pid == app.pid }.sorted { $0.id < $1.id }
    }

    func window(id: WindowID) -> WindowInfo? { windowsByID[id] }

    func activeWindow() -> WindowInfo? {
        guard let id = activeWindowID, let window = windowsByID[id] else { return nil }
        return window
    }

    func frontmostPID() -> Int32? { frontmost }
    func cursorPosition() -> Point? { cursor }
    func screens() -> [ScreenInfo] { screenList }

    func setFrame(_ frame: Rect, of window: WindowID) throws {
        if failSetFrame { throw ToggleError("setFrame failed") }
        setFrameCalls.append((frame, window))
        windowsByID[window]?.frame = frame
    }

    func focus(_ window: WindowID) throws {
        if failFocus { throw ToggleError("focus failed") }
        activeWindowID = window
        frontmost = windowsByID[window]?.app.pid
    }

    func setMinimized(_ minimized: Bool, window: WindowID) throws {
        windowsByID[window]?.isMinimized = minimized
    }

    func setHidden(_ hidden: Bool, pid: Int32) {
        if hidden { hiddenPIDs.insert(pid) } else { hiddenPIDs.remove(pid) }
    }

    func isHidden(pid: Int32) -> Bool { hiddenPIDs.contains(pid) }

    func activate(pid: Int32) {
        activated.append(pid)
        frontmost = pid
    }

    func launch(_ spec: LaunchSpec, arguments: [String], workingDirectory: String?) throws {
        launches.append((spec, workingDirectory))
        pollsSinceLaunch = 0
    }
}

@MainActor
final class TestClock {
    var instant = ContinuousClock.now
    func advance(_ duration: Duration) { instant = instant.advanced(by: duration) }
}

/// Holds spawn polls until the test opens it, so a toggle stays in flight.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

@MainActor
@Suite struct ToggleTests {
    let screen = ScreenInfo(
        name: "Main", frame: Rect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: Rect(x: 0, y: 25, width: 1440, height: 875))
    let target = Rect(x: 0, y: 25, width: 720, height: 875)
    let originalFrame = Rect(x: 10, y: 10, width: 300, height: 200)

    let identityA = AppIdentity(pid: 100, bundleID: "com.test.a", name: "A", executableName: "a")
    let identityB = AppIdentity(pid: 200, bundleID: "com.test.b", name: "B", executableName: "b")
    let identityC = AppIdentity(pid: 300, bundleID: "com.test.c", name: "C", executableName: "c")

    func makeConfig(
        _ name: String, key: String, bundleID: String, hide: HideBehavior = .hide,
        attach: AttachMode = .findOrStart, hideOnFocusLost: Bool = false
    ) throws -> AppConfig {
        AppConfig(
            name: name, hotkey: try Hotkey.parse(key), bundleID: bundleID,
            launch: .bundleID(bundleID), attachMode: attach, hideBehavior: hide,
            hideOnFocusLost: hideOnFocusLost,
            placement: PlacementConfig(width: .percent(50), height: .percent(100)))
    }

    func window(_ id: WindowID, _ app: AppIdentity) -> WindowInfo {
        WindowInfo(id: id, app: app, title: "w\(id)", frame: originalFrame, isMinimized: false)
    }

    func makeFake(_ identities: AppIdentity...) -> FakeWindowManager {
        let fake = FakeWindowManager()
        fake.screenList = [screen]
        for (index, identity) in identities.enumerated() {
            fake.apps.append(identity)
            fake.windowsByID[WindowID(index + 1)] = window(WindowID(index + 1), identity)
        }
        return fake
    }

    func makeService(
        _ configs: [AppConfig], _ fake: FakeWindowManager, clock: TestClock = TestClock(),
        timing: ToggleTiming = ToggleTiming(spawnPollAttempts: 5), gate: Gate? = nil
    ) -> ToggleService {
        ToggleService(
            apps: configs, windowManager: fake, timing: timing, now: { clock.instant },
            sleep: { _ in await gate?.wait() })
    }

    /// Yields until `condition` holds, failing the test if it never does.
    func yield(until condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() {
            await Task.yield()
        }
        #expect(condition())
    }

    @Test func showsExistingWindow() async throws {
        let fake = makeFake(identityA)
        fake.hiddenPIDs = [100]
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")], fake)

        try await service.toggle("a")

        #expect(!fake.isHidden(pid: 100))
        #expect(fake.windowsByID[1]?.frame == target)
        #expect(fake.setFrameCalls.count == 1)
        #expect(fake.activeWindowID == 1)
        #expect(service.visibleAppName == "a")
        #expect(service.apps["a"]?.trackedWindowID == 1)
        #expect(service.apps["a"]?.restoreFrame == originalFrame)
        #expect(fake.launches.isEmpty)
    }

    @Test func unminimizesOnShow() async throws {
        let fake = makeFake(identityA)
        fake.windowsByID[1]?.isMinimized = true
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")], fake)
        try await service.toggle("a")
        #expect(fake.windowsByID[1]?.isMinimized == false)
    }

    @Test func toggleAgainHidesWithHideBehavior() async throws {
        let fake = makeFake(identityA)
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")], fake)
        try await service.toggle("a")
        try await service.toggle("a")
        #expect(fake.hiddenPIDs == [100])
        #expect(service.visibleAppName == nil)
        #expect(!service.isVisible("a"))
    }

    @Test func toggleAgainMinimizes() async throws {
        let fake = makeFake(identityA)
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a", hide: .minimize)], fake)
        try await service.toggle("a")
        try await service.toggle("a")
        #expect(fake.windowsByID[1]?.isMinimized == true)
        #expect(fake.hiddenPIDs.isEmpty)
        #expect(service.visibleAppName == nil)
        // Showing again restores it.
        try await service.toggle("a")
        #expect(fake.windowsByID[1]?.isMinimized == false)
        #expect(service.visibleAppName == "a")
    }

    @Test func toggleAgainMovesOffscreen() async throws {
        let fake = makeFake(identityA)
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a", hide: .offscreen)], fake)
        try await service.toggle("a")
        try await service.toggle("a")
        let expected = offscreenRect(for: target, screens: [screen])
        #expect(expected == Rect(x: 1439, y: 899, width: 720, height: 875))
        #expect(fake.windowsByID[1]?.frame == expected)
        #expect(fake.hiddenPIDs.isEmpty)
        #expect(service.visibleAppName == nil)
    }

    @Test func visibleButNotFocusedReshows() async throws {
        let fake = makeFake(identityA)
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")], fake)
        try await service.toggle("a")
        fake.activeWindowID = nil
        try await service.toggle("a")
        #expect(fake.hiddenPIDs.isEmpty)
        #expect(service.visibleAppName == "a")
        #expect(fake.setFrameCalls.count == 2)
        #expect(fake.activeWindowID == 1)
    }

    @Test func showingOneAppHidesTheOther() async throws {
        let fake = makeFake(identityA, identityB)
        let service = makeService(
            [
                try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a"),
                try makeConfig("b", key: "ctrl+b", bundleID: "com.test.b"),
            ], fake)
        try await service.toggle("a")
        #expect(service.visibleAppName == "a")
        try await service.toggle("b")
        #expect(service.visibleAppName == "b")
        #expect(fake.hiddenPIDs == [100])
        #expect(!service.isVisible("a"))
        #expect(service.isVisible("b"))
        #expect(fake.windowsByID[2]?.frame == target)
    }

    @Test func unknownAppThrows() async {
        let fake = makeFake()
        let service = makeService([], fake)
        await #expect(throws: ToggleError.self) { try await service.toggle("nope") }
    }

    @Test func findModeWithoutWindowThrows() async throws {
        let fake = makeFake()
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a", attach: .find)], fake)
        let error = try await #require(throws: ToggleError.self) { try await service.toggle("a") }
        #expect(error.message.contains("no existing window"))
        #expect(fake.launches.isEmpty)
        #expect(service.visibleAppName == nil)
    }

    @Test func findOrStartLaunchesAndPollsUntilWindowAppears() async throws {
        let fake = makeFake()
        fake.spawn = (identityA, window(7, identityA))
        fake.spawnAfterPolls = 3
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")], fake)

        try await service.toggle("a")

        #expect(fake.launches.count == 1)
        #expect(fake.launches.first?.spec == .bundleID("com.test.a"))
        #expect(fake.windowsByID[7]?.frame == target)
        #expect(service.visibleAppName == "a")
        #expect(service.apps["a"]?.trackedWindowID == 7)
    }

    @Test func findOrStartTimesOut() async throws {
        let fake = makeFake()
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")], fake,
            timing: ToggleTiming(spawnPollAttempts: 3))
        let error = try await #require(throws: ToggleError.self) { try await service.toggle("a") }
        #expect(error.message.contains("no matching window appeared"))
        #expect(fake.launches.count == 1)
        #expect(service.visibleAppName == nil)
        // The pending-spawn marker is cleared, so a later toggle launches again.
        _ = try? await service.toggle("a")
        #expect(fake.launches.count == 2)
    }

    @Test func spawnTooLateTimesOut() async throws {
        let fake = makeFake()
        fake.spawn = (identityA, window(7, identityA))
        fake.spawnAfterPolls = 10
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")], fake,
            timing: ToggleTiming(spawnPollAttempts: 3))
        await #expect(throws: ToggleError.self) { try await service.toggle("a") }
    }

    @Test func hotkeyDebounce() async throws {
        let fake = makeFake(identityA)
        let clock = TestClock()
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")], fake, clock: clock)

        await service.handleHotkey("a")
        #expect(service.visibleAppName == "a")

        clock.advance(.milliseconds(100))
        await service.handleHotkey("a")
        #expect(service.visibleAppName == "a")  // ignored
        #expect(fake.setFrameCalls.count == 1)

        clock.advance(.milliseconds(200))
        await service.handleHotkey("a")
        #expect(service.visibleAppName == nil)  // toggled off
        #expect(fake.hiddenPIDs == [100])
    }

    @Test func hotkeyFailureIsSwallowed() async throws {
        let fake = makeFake()
        let clock = TestClock()
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a", attach: .find)], fake,
            clock: clock)
        await service.handleHotkey("a")
        #expect(service.visibleAppName == nil)
        #expect(service.apps["a"]?.lastError?.contains("no existing window") == true)

        fake.apps.append(identityA)
        fake.windowsByID[1] = window(1, identityA)
        clock.advance(.seconds(1))
        await service.handleHotkey("a")
        #expect(service.visibleAppName == "a")
        #expect(service.apps["a"]?.lastError == nil)
    }

    @Test func focusChangeHidesWhenFocusLost() async throws {
        let fake = makeFake(identityA, identityC)
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a", hideOnFocusLost: true)],
            fake)
        try await service.toggle("a")

        service.handleFocusChange()
        #expect(service.visibleAppName == "a")  // still focused

        fake.activeWindowID = 2
        fake.frontmost = 300
        service.handleFocusChange()
        #expect(service.visibleAppName == nil)
        #expect(fake.hiddenPIDs == [100])
    }

    @Test func focusChangeIgnoredWithoutOption() async throws {
        let fake = makeFake(identityA, identityC)
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")], fake)
        try await service.toggle("a")
        fake.activeWindowID = 2
        service.handleFocusChange()
        #expect(service.visibleAppName == "a")
        #expect(fake.hiddenPIDs.isEmpty)
    }

    @Test func focusChangeWithNothingVisibleIsNoop() throws {
        let fake = makeFake(identityA)
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a", hideOnFocusLost: true)],
            fake)
        service.handleFocusChange()
        #expect(fake.hiddenPIDs.isEmpty)
    }

    @Test func restoreTrackedWindows() async throws {
        let fake = makeFake(identityA)
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")], fake)
        try await service.toggle("a")
        #expect(fake.windowsByID[1]?.frame == target)
        service.restoreTrackedWindows()
        #expect(fake.windowsByID[1]?.frame == originalFrame)
    }

    @Test func restoreWithoutTrackedWindowDoesNothing() throws {
        let fake = makeFake(identityA)
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")], fake)
        service.restoreTrackedWindows()
        #expect(fake.setFrameCalls.isEmpty)
    }

    @Test func replaceAppsKeepsStateAndRestoresRemoved() async throws {
        let fake = makeFake(identityA, identityB)
        let configA = try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")
        let configB = try makeConfig("b", key: "ctrl+b", bundleID: "com.test.b")
        let service = makeService([configA, configB], fake)
        try await service.toggle("a")

        var changedA = configA
        changedA.hideBehavior = .minimize
        service.replaceApps([changedA, configB])
        #expect(service.apps["a"]?.trackedWindowID == 1)
        #expect(service.isVisible("a"))
        #expect(service.apps["a"]?.config.hideBehavior == .minimize)
        #expect(service.visibleAppName == "a")
        #expect(service.order == ["a", "b"])

        service.replaceApps([configB])
        #expect(fake.windowsByID[1]?.frame == originalFrame)
        #expect(service.apps["a"] == nil)
        #expect(service.visibleAppName == nil)
        #expect(service.order == ["b"])
    }

    @Test func minimizeRestoresFocusToPreviousFrontmost() async throws {
        let fake = makeFake(identityA, identityC)
        fake.frontmost = 300
        fake.activeWindowID = 2
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a", hide: .minimize)], fake)
        try await service.toggle("a")
        #expect(fake.frontmost == 100)
        #expect(service.apps["a"]?.previousFrontmostPID == 300)
        try await service.toggle("a")
        #expect(fake.activated == [300])
        #expect(fake.frontmost == 300)
    }

    @Test func screenSelectionByNameAndCursor() async throws {
        let fake = makeFake(identityA)
        let second = ScreenInfo(
            name: "Second", frame: Rect(x: 1440, y: 0, width: 1000, height: 800),
            visibleFrame: Rect(x: 1440, y: 0, width: 1000, height: 800))
        fake.screenList = [screen, second]
        fake.cursor = Point(x: 1500, y: 10)
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")], fake)
        try await service.toggle("a")
        #expect(fake.windowsByID[1]?.frame == Rect(x: 1440, y: 0, width: 500, height: 800))

        var configured = try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")
        configured.placement.screen = "main"
        let fake2 = makeFake(identityA)
        fake2.screenList = [screen, second]
        fake2.cursor = Point(x: 1500, y: 10)
        let service2 = makeService([configured], fake2)
        try await service2.toggle("a")
        #expect(fake2.windowsByID[1]?.frame == target)
    }

    @Test func placementTooLargeThrows() async throws {
        let fake = makeFake(identityA)
        var config = try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")
        config.placement.width = .pixels(5000)
        let service = makeService([config], fake)
        let error = try await #require(throws: ToggleError.self) { try await service.toggle("a") }
        #expect(error.message.contains("invalid placement"))
    }

    // MARK: - Serialization

    @Test func serializationKeepsOneVisible() async throws {
        let fake = makeFake(identityB)
        fake.spawn = (identityA, window(7, identityA))
        fake.spawnAfterPolls = 1
        let gate = Gate()
        let service = makeService(
            [
                try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a"),
                try makeConfig("b", key: "ctrl+b", bundleID: "com.test.b"),
            ], fake, gate: gate)

        let first = Task { await service.handleHotkey("a") }
        await yield(until: { fake.launches.count == 1 })
        let second = Task { await service.handleHotkey("b") }
        for _ in 0..<20 { await Task.yield() }
        // B waits for A's start instead of showing in between.
        #expect(service.visibleAppName == nil)

        await gate.open()
        await first.value
        await second.value

        #expect(service.visibleAppName == "b")
        #expect(fake.hiddenPIDs == [100])
        #expect(["a", "b"].filter(service.isVisible) == ["b"])
    }

    @Test func secondPressDuringPendingStartReturnsEarly() async throws {
        let fake = makeFake()
        fake.spawn = (identityA, window(7, identityA))
        fake.spawnAfterPolls = 1
        let gate = Gate()
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")], fake, gate: gate)

        let first = Task { try await service.toggle("a") }
        await yield(until: { fake.launches.count == 1 })
        try await service.toggle("a")  // returns at once
        await gate.open()
        try await first.value

        #expect(fake.launches.count == 1)
        #expect(service.visibleAppName == "a")
    }

    // MARK: - Restore

    @Test func restoreFrameSurvivesLostTracking() async throws {
        let fake = makeFake(identityA)
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a", attach: .find)], fake)
        try await service.toggle("a")
        #expect(fake.windowsByID[1]?.frame == target)

        // The window disappears from AX for a moment, so tracking is dropped.
        let placed = try #require(fake.windowsByID[1])
        fake.windowsByID[1] = nil
        await #expect(throws: ToggleError.self) { try await service.toggle("a") }
        #expect(service.apps["a"]?.trackedWindowID == nil)

        fake.windowsByID[1] = placed
        try await service.toggle("a")
        #expect(service.apps["a"]?.restoreFrame == originalFrame)
        service.restoreTrackedWindows()
        #expect(fake.windowsByID[1]?.frame == originalFrame)
    }

    @Test func restoreUsesRestoreWindowAfterTrackingCleared() async throws {
        let fake = makeFake(identityA)
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a", attach: .find)], fake)
        try await service.toggle("a")
        let placed = try #require(fake.windowsByID[1])
        fake.windowsByID[1] = nil
        _ = try? await service.toggle("a")
        fake.windowsByID[1] = placed
        service.restoreTrackedWindows()
        #expect(fake.windowsByID[1]?.frame == originalFrame)
    }

    @Test func parkedOffscreenFrameIsNotRecorded() async throws {
        let fake = makeFake(identityA)
        let parked = offscreenRect(for: originalFrame, screens: [screen])
        fake.windowsByID[1]?.frame = parked
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a", hide: .offscreen)], fake)
        try await service.toggle("a")
        #expect(fake.windowsByID[1]?.frame == target)
        #expect(service.apps["a"]?.restoreFrame == nil)

        service.restoreTrackedWindows()
        #expect(fake.windowsByID[1]?.frame == target)
        #expect(fake.setFrameCalls.count == 1)
    }

    @Test func restoreUnhidesHiddenApp() async throws {
        let fake = makeFake(identityA)
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")], fake)
        try await service.toggle("a")
        try await service.toggle("a")
        #expect(fake.hiddenPIDs == [100])

        service.restoreTrackedWindows()
        #expect(fake.hiddenPIDs.isEmpty)
        #expect(fake.windowsByID[1]?.frame == originalFrame)
    }

    @Test func restoreUnminimizesMinimizedWindow() async throws {
        let fake = makeFake(identityA)
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a", hide: .minimize)], fake)
        try await service.toggle("a")
        try await service.toggle("a")
        #expect(fake.windowsByID[1]?.isMinimized == true)

        service.restoreTrackedWindows()
        #expect(fake.windowsByID[1]?.isMinimized == false)
        #expect(fake.windowsByID[1]?.frame == originalFrame)
    }

    @Test func replaceAppsWithChangedMatcherReleasesWindow() async throws {
        let fake = makeFake(identityA, identityB)
        let configA = try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")
        let configB = try makeConfig("b", key: "ctrl+b", bundleID: "com.test.b")
        let service = makeService([configA, configB], fake)
        try await service.toggle("a")

        var changedA = configA
        changedA.bundleID = "com.test.c"
        service.replaceApps([changedA, configB])
        #expect(fake.windowsByID[1]?.frame == originalFrame)
        #expect(service.apps["a"]?.trackedWindowID == nil)
        #expect(service.apps["a"]?.trackedPID == nil)
        #expect(service.apps["a"]?.restoreFrame == nil)
        #expect(service.apps["a"]?.restoreWindowID == nil)
        #expect(!service.isVisible("a"))
        #expect(service.visibleAppName == nil)
    }

    // MARK: - Window resolution and focus

    @Test func windowTrackedByAnotherAppIsNotShared() async throws {
        let fake = makeFake(identityA)
        fake.windowsByID[2] = window(2, identityA)
        let service = makeService(
            [
                try makeConfig("x", key: "ctrl+x", bundleID: "com.test.a", hide: .minimize),
                try makeConfig("y", key: "ctrl+y", bundleID: "com.test.a", hide: .minimize),
            ], fake)
        try await service.toggle("x")
        try await service.toggle("y")
        #expect(service.apps["x"]?.trackedWindowID == 1)
        #expect(service.apps["y"]?.trackedWindowID == 2)
        #expect(service.visibleAppName == "y")
    }

    @Test func focusOnSameAppWindowDoesNotHideWithHideBehavior() async throws {
        let fake = makeFake(identityA)
        fake.windowsByID[2] = window(2, identityA)
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a", hideOnFocusLost: true)],
            fake)
        try await service.toggle("a")
        #expect(service.apps["a"]?.trackedWindowID == 1)

        fake.activeWindowID = 2
        service.handleFocusChange()
        #expect(service.visibleAppName == "a")
        #expect(fake.hiddenPIDs.isEmpty)
    }

    @Test func focusOnSameAppWindowHidesWithMinimize() async throws {
        let fake = makeFake(identityA)
        fake.windowsByID[2] = window(2, identityA)
        let service = makeService(
            [
                try makeConfig(
                    "a", key: "ctrl+a", bundleID: "com.test.a", hide: .minimize,
                    hideOnFocusLost: true)
            ], fake)
        try await service.toggle("a")

        fake.activeWindowID = 2
        service.handleFocusChange()
        #expect(service.visibleAppName == nil)
        #expect(fake.windowsByID[1]?.isMinimized == true)
    }

    @Test func appTerminationClearsVisibilityAndTracking() async throws {
        let fake = makeFake(identityA, identityC)
        fake.frontmost = 300
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")], fake)
        try await service.toggle("a")
        #expect(service.apps["a"]?.previousFrontmostPID == 300)
        var changes = 0
        service.onStateChange = { changes += 1 }

        service.handleAppTerminated(pid: 300)
        #expect(service.apps["a"]?.previousFrontmostPID == nil)
        #expect(service.isVisible("a"))
        #expect(changes == 1)

        service.handleAppTerminated(pid: 100)
        #expect(!service.isVisible("a"))
        #expect(service.visibleAppName == nil)
        #expect(service.apps["a"]?.trackedWindowID == nil)
        #expect(service.apps["a"]?.restoreFrame == nil)
        #expect(service.apps["a"]?.restoreWindowID == nil)
        #expect(service.trackedPIDs.isEmpty)
        #expect(changes == 2)

        service.handleAppTerminated(pid: 999)
        #expect(changes == 2)
    }

    // MARK: - Failures and UI toggles

    @Test func setFrameFailureStillShowsAndNextToggleHides() async throws {
        let fake = makeFake(identityA)
        fake.failSetFrame = true
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")], fake)
        try await service.toggle("a")
        #expect(service.isVisible("a"))
        #expect(fake.activeWindowID == 1)

        try await service.toggle("a")
        #expect(!service.isVisible("a"))
        #expect(fake.hiddenPIDs == [100])
    }

    @Test func focusFailureStillShowsAndNextToggleHides() async throws {
        let fake = makeFake(identityA)
        fake.failFocus = true
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")], fake)
        try await service.toggle("a")
        #expect(service.isVisible("a"))
        #expect(fake.windowsByID[1]?.frame == target)

        // The user focuses the window by hand; the next press hides it.
        fake.activeWindowID = 1
        try await service.toggle("a")
        #expect(!service.isVisible("a"))
        #expect(fake.hiddenPIDs == [100])
    }

    @Test func hideIfVisibleHidesWhenAnotherWindowIsActive() async throws {
        let fake = makeFake(identityA, identityC)
        let service = makeService(
            [try makeConfig("a", key: "ctrl+a", bundleID: "com.test.a")], fake)
        try await service.toggle("a")
        fake.activeWindowID = 2

        try await service.toggle("a", hideIfVisible: true)
        #expect(service.visibleAppName == nil)
        #expect(fake.hiddenPIDs == [100])
    }
}
