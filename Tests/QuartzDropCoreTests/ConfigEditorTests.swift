import Testing

@testable import QuartzDropCore

@Suite struct ConfigEditorTests {
    let tables = """
        [[app]]
        name = "a"
        menu_bar = true

        """

    @Test func replacesExistingAssignment() {
        let text = "log_level = \"info\"\nmenu_bar = true  # icon\n\n" + tables
        let edited = ConfigEditor.setTopLevel("menu_bar", to: false, in: text)
        #expect(edited == "log_level = \"info\"\nmenu_bar = false  # icon\n\n" + tables)
    }

    @Test func replacesQuotedKeyInPlace() {
        for quote in ["\"", "'"] {
            let text = "\(quote)menu_bar\(quote) = true  # icon\n\n" + tables
            let edited = ConfigEditor.setTopLevel("menu_bar", to: false, in: text)
            #expect(edited == "menu_bar = false  # icon\n\n" + tables)
        }
    }

    @Test func uncommentsCommentedAssignment() {
        let text = "# menu_bar = true      # Show the icon\n#   more help\n\n" + tables
        let edited = ConfigEditor.setTopLevel("menu_bar", to: false, in: text)
        #expect(edited == "menu_bar = false      # Show the icon\n#   more help\n\n" + tables)
    }

    @Test func insertsBeforeFirstTable() {
        let text = "# header\n\n" + tables
        let edited = ConfigEditor.setTopLevel("menu_bar", to: false, in: text)
        #expect(edited == "# header\n\nmenu_bar = false\n\n" + tables)
    }

    @Test func doesNotTouchKeysInsideTables() {
        let edited = ConfigEditor.setTopLevel("menu_bar", to: false, in: tables)
        #expect(edited == "menu_bar = false\n\n" + tables)
    }

    @Test func doesNotMatchKeyPrefix() {
        let text = "menu_bar_extra = true\n" + tables
        let edited = ConfigEditor.setTopLevel("menu_bar", to: false, in: text)
        #expect(edited.hasPrefix("menu_bar_extra = true\nmenu_bar = false\n\n[[app]]"))
    }

    @Test func editedExampleConfigParses() throws {
        var text = exampleConfig
        text = ConfigEditor.setTopLevel("menu_bar", to: false, in: text)
        let config = try Config.parse(text)
        #expect(!config.menuBar)
    }
}
