import Foundation
import Testing

@testable import QuartzDropCore

@Suite struct ExampleConfigTests {
    @Test func exampleConfigParses() throws {
        let config = try Config.parse(exampleConfig)
        #expect(!config.apps.isEmpty)
    }

    @Test func exampleConfigMatchesResourceFile() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("resources/example-config.toml")
        var text = try String(contentsOf: url, encoding: .utf8)
        if text.hasSuffix("\n") { text.removeLast() }
        #expect(exampleConfig == text)
    }
}
