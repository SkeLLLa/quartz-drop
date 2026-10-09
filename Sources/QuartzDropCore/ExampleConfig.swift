// Hand-kept mirror of resources/example-config.toml; ExampleConfigTests keeps them in sync.

public let exampleConfig = #"""
    # quartz-drop configuration. Reloaded automatically when this file changes.
    # Full reference: https://github.com/SkeLLLa/quartz-drop/blob/master/docs/configuration.md

    # log_level = "error"  # error | warn | info | debug | trace | off (default: error)
    #                        # Override with --log-level / -v or the QUARTZ_DROP_LOG env var.
    # menu_bar = true      # Show the menu bar icon (default: true). Without it, launch the app
    #                        # again (or `open -a QuartzDrop`) to open Settings.

    [[app]]
    name = "finder"
    # Modifiers: ctrl, shift, alt/option, cmd. Keys: a-z, 0-9, f1-f20, grave, space, arrows, ...
    hotkey = "ctrl+alt+f"
    # Match and start apps by bundle identifier (`osascript -e 'id of app "Finder"'` prints it).
    bundle_id = "com.apple.finder"
    attach_mode = "find-or-start"
    # "hide" (default) hides the whole app like ⌘H; "minimize" sends the window to the Dock;
    # "offscreen" parks the window in the bottom-right corner of the right-most screen.
    hide_behavior = "minimize"
    # Hide when another window becomes active, like a drop-down terminal.
    hide_on_focus_lost = true

    [app.placement]
    width = "50%"
    height = "100%"
    position = "left"
    # Always show on this display instead of the screen under the cursor
    # (System Settings → Displays shows the names).
    # screen = "Built-in Retina Display"

    [[app]]
    name = "safari"
    hotkey = "ctrl+alt+s"
    # A path ending in .app is opened with Launch Services; the app name is used for matching.
    filename = "/Applications/Safari.app"
    attach_mode = "find-or-start"

    [app.placement]
    width = "50%"
    height = "100%"
    position = "right"

    [[app]]
    name = "terminal"
    hotkey = "ctrl+grave"
    bundle_id = "com.apple.Terminal"
    # Only attach to windows whose title matches (case-insensitive regex).
    # window_title = "dropdown"
    attach_mode = "find-or-start"
    hide_behavior = "hide"
    hide_on_focus_lost = true

    [app.placement]
    width = "100%"
    height = "40%"
    position = "top"

    [[app]]
    name = "notes"
    hotkey = "ctrl+alt+n"
    # Bare executables can be started with an explicit command; process_name matches the bundle
    # id, app name, or executable name (case-insensitive regex).
    process_name = "^Notes$"
    command = ["/usr/bin/open", "-a", "Notes"]
    attach_mode = "find-or-start"
    hide_behavior = "offscreen"

    [app.placement]
    width = "800px"
    height = "60%"
    position = "center"
    """#
