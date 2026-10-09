import Testing

@testable import QuartzDropCore

@Suite struct ExecutableTests {
    @Test func searchDirectoriesKeepOrderAndDropDuplicates() {
        let dirs = executableSearchDirectories(
            path: "/usr/bin::/opt/homebrew/bin:/bin:/usr/bin", home: "/Users/me")
        #expect(
            dirs == [
                "/usr/bin", "/opt/homebrew/bin", "/bin", "/usr/local/bin", "/Users/me/.local/bin",
            ])
    }

    @Test func searchDirectoriesWithoutPath() {
        #expect(
            executableSearchDirectories(path: nil, home: "/h")
                == ["/opt/homebrew/bin", "/usr/local/bin", "/h/.local/bin"])
    }

    @Test func nameWithSlashIsReturnedAsIs() {
        let result = resolveExecutable(
            "/Applications/kitty.app/Contents/MacOS/kitty", path: "/usr/bin", home: "/h",
            isExecutable: { _ in false })
        #expect(result == "/Applications/kitty.app/Contents/MacOS/kitty")
        #expect(
            resolveExecutable("bin/tool", path: nil, home: "/h", isExecutable: { _ in false })
                == "bin/tool")
    }

    @Test func tildeIsExpanded() {
        let result = resolveExecutable(
            "~/bin/tool", path: nil, home: "/Users/me", isExecutable: { _ in false })
        #expect(result == "/Users/me/bin/tool")
    }

    @Test func firstExecutableMatchWins() {
        let executables: Set<String> = ["/b/kitty", "/opt/homebrew/bin/kitty"]
        let result = resolveExecutable(
            "kitty", path: "/a:/b", home: "/h", isExecutable: { executables.contains($0) })
        #expect(result == "/b/kitty")
    }

    @Test func nilWhenNothingMatches() {
        #expect(
            resolveExecutable("kitty", path: "/a:/b", home: "/h", isExecutable: { _ in false })
                == nil)
    }
}
