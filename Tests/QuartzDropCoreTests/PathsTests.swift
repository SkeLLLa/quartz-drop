import QuartzDropCore
import Testing

@Suite struct PathsTests {
    private func resolve(_ path: String) -> String {
        absolutePath(path, currentDirectory: "/work/dir", home: "/Users/me")
    }

    @Test func joinsRelativePathToCurrentDirectory() {
        #expect(resolve("config.toml") == "/work/dir/config.toml")
        #expect(resolve("sub/config.toml") == "/work/dir/sub/config.toml")
        #expect(resolve("./config.toml") == "/work/dir/config.toml")
    }

    @Test func standardizesParentComponents() {
        #expect(resolve("../other/config.toml") == "/work/other/config.toml")
        #expect(resolve("/a/b/../c/./config.toml") == "/a/c/config.toml")
    }

    @Test func expandsTilde() {
        #expect(resolve("~") == "/Users/me")
        #expect(resolve("~/x") == "/Users/me/x")
        #expect(
            resolve("~/.config/quartz-drop/config.toml")
                == "/Users/me/.config/quartz-drop/config.toml")
    }

    @Test func leavesAbsolutePathUnchanged() {
        #expect(resolve("/etc/quartz-drop/config.toml") == "/etc/quartz-drop/config.toml")
    }
}
