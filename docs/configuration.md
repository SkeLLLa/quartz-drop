# Configuration

The config file is TOML and contains one or more `[[app]]` entries. The default path is
`~/.config/quartz-drop/config.toml`; use `--config PATH` to change it. The file is reloaded
automatically when it changes (in-place saves and symlinked configs work, and replacing the config
directory is survived), and `quartz-drop check` validates it without starting the app.

## Top-Level Fields

- `log_level`: optional log level. One of `error`, `warn`, `info`, `debug`, `trace`, `off`. Defaults to `error`.
- `menu_bar`: optional boolean; show the menu bar icon. Defaults to `true`. When `false`, launching
  the app again while it is running (or `open -a QuartzDrop`) opens Settings, where the icon can be
  turned back on.

The menu bar menu item "Hide Menu Bar Icon" (after confirmation) and the Settings → General →
Menu Bar toggle "Show menu bar icon" writes `menu_bar` to the config file in place. An existing
top-level assignment is replaced, a commented `# menu_bar = ...` line is uncommented, otherwise the
assignment is inserted before the first table. Comments are kept. When quartz-drop toggles the icon
itself, it reloads the config at once.

The effective log level is resolved with the following priority (highest first):

1. `QUARTZ_DROP_LOG` environment variable
2. `--log-level <LEVEL>` CLI flag
3. `-v` / `-vv` CLI flags (`info` / `debug`)
4. Config `log_level`
5. Default `error`

## Core Fields

- `name`: required unique app identifier, at most 64 characters
- `hotkey`: required shortcut string such as `ctrl+alt+f`; see [Hotkeys](#hotkeys)
- `bundle_id`: bundle identifier, for example `com.apple.Terminal`; matches and can launch the app
- `filename`: app name (`Safari`) or path (`/Applications/Safari.app`, or an executable path)
- `command`: explicit spawn command array, for example `["/usr/bin/open", "-a", "Notes"]`. If
  `command[0]` has no `/`, it is looked up in `PATH`, then `/opt/homebrew/bin`, `/usr/local/bin`, and
  `~/.local/bin` (GUI apps get a minimal `PATH`).
- `arguments`: optional array of strings passed to the app launched from `filename`, `bundle_id`, or
  an app name; setting both `command` and `arguments` is an error
- `process_name`: optional case-insensitive regex matched against bundle ID, app name, and executable name
- `window_title`: optional case-insensitive regex matched against the window title
- `attach_mode`: `find` or `find-or-start` (default)
- `working_directory`: optional absolute directory; a relative path is an error, a directory that
  does not exist on this Mac is ignored (see [Ignored on macOS](#differences-from-plasma-drop))
- `hide_behavior`: `hide` (default), `minimize`, or `offscreen`
- `hide_on_focus_lost`: optional boolean; hide the managed app when another window becomes active. Defaults to `false`.

At least one of `bundle_id`, `filename`, `process_name`, or `window_title` is required. With
`attach_mode = "find-or-start"` without any of `command`, `bundle_id`, or `filename` produces a
warning: the app cannot be started and can only attach to an already-running window.

## Hotkeys

A hotkey is zero or more modifiers followed by one key, joined with `+`, for example `ctrl+alt+f`.
Each modifier may appear once, and two apps cannot share a hotkey.

| Modifier | Accepted names                         |
| -------- | -------------------------------------- |
| Control  | `ctrl`, `control`                      |
| Shift    | `shift`                                |
| Option   | `alt`, `option`, `opt`                 |
| Command  | `cmd`, `command`, `super`, `meta`, `win` |

`super`, `meta`, and `win` map to Cmd, so plasma-drop hotkeys parse unchanged.

Keys:

- letters `a`-`z` and digits `0`-`9`
- function keys `f1`-`f20` (`f21`-`f24` from plasma-drop configs are not supported on macOS; that
  app is skipped with an "ignored on macOS" note)
- `grave` (`backtick`, `` ` ``), `section` (`§`), `space`, `tab`, `return` (`enter`), `escape` (`esc`),
  `delete` (`backspace`), `forwarddelete`
- punctuation: `minus` (`-`), `equal` (`=`), `bracketleft` (`[`), `bracketright` (`]`), `semicolon`
  (`;`), `quote` (`'`), `backslash` (`\`), `comma` (`,`), `period` (`.`), `slash` (`/`)
- navigation: `left`, `right`, `up`, `down`, `home`, `end`, `pageup`, `pagedown`

On ISO keyboards the key below Esc is `section` (§), and `grave` is the key left of Z. For the
classic drop-down-terminal shortcut on ISO Macs use `section`.

Letter and punctuation keys follow the physical ANSI key position, so on non-QWERTY layouts the
shortcut binds by position rather than by printed letter. Hotkeys use Carbon `RegisterEventHotKey`,
which needs no Input Monitoring permission.

## Matching Behavior

An existing window matches an app entry as follows:

- `bundle_id` always filters: the running app's bundle identifier must equal it (case-insensitive).
- `process_name`, when set, must match at least one of the bundle ID, app name, or executable name.
- `window_title`, when set, must match the window title.
- `filename` is a plain case-insensitive identity matcher on the file name without `.app`, compared
  with the bundle ID, app name, and executable name. It is used only when neither `process_name` nor
  `window_title` nor `bundle_id` is set.

Dock-hidden (accessory) apps can be matched too. When several windows match, a non-minimized one is
preferred and the ambiguity is logged. A window already tracked by another entry is only used if
nothing else matches. Changing an entry's matchers releases its previously tracked window.

## Launch Behavior

With `attach_mode = "find-or-start"` and no matching window, the app is started. The launch method
is chosen in this order:

1. `command`, used exactly as the argument vector
2. `bundle_id`, launched or reopened through Launch Services
3. `filename`: a path ending in `.app` is opened through Launch Services; any other path is run as
   an executable; a bare name is opened by app name, like `open -a <name>`

`arguments` apply to the `filename` launch. For a bare executable path (contains `/`, not `.app`)
the argument vector is `[filename] + arguments`. For a `bundle_id`, `.app` path, or app name, the
arguments are passed to the app when it is opened (`OpenConfiguration.arguments`).
quartz-drop then waits up to about 20 seconds for a window to appear. With `attach_mode = "find"`,
nothing is started and only existing windows are used.

`command` is useful for wrapper-based apps where launch identity and window identity differ; pair it
with `process_name` or `bundle_id` for matching.

## Hiding

Only one managed app is visible at a time: showing one hides the others. If the app is visible but
not focused, its hotkey brings it forward instead of hiding it.

- `hide_behavior = "hide"` (default) hides the whole application, like Cmd-H. Works for every app and
  leaves nothing on screen.
- `hide_behavior = "minimize"` minimizes only the managed window into the Dock.
- `hide_behavior = "offscreen"` parks only the managed window. macOS will not move a window fully off
  every display, so it is placed at the bottom-right corner of the right-most display, leaving a 1px
  sliver visible.

Set `hide_on_focus_lost = true` for a drop-down-terminal-style window that hides when another window
becomes active. With `hide_behavior = "hide"` it does not hide when focus moves to another window of
the same app.

Toggles run one at a time, so a press waits for an app that is still starting. Original window
frames are restored on quit (including Ctrl-C, SIGTERM, and closing the terminal), and when an entry
is removed from the config; hidden or minimized apps are shown again. Fixed-size windows are moved
but not resized.

```toml
[[app]]
name = "notes"
hotkey = "ctrl+alt+n"
bundle_id = "com.apple.Notes"
hide_behavior = "minimize"
hide_on_focus_lost = true
```

## Placement

Each app may define:

```toml
[app.placement]
width = "50%"
height = "100%"
position = "left"
offset_x = "0px"
offset_y = "0px"
screen = "Built-in Retina Display"
```

- `width`, `height`: `"50%"` or `"640px"`. Default `"100%"`. Must be positive; percentages at most 100.
- `position`: one of `top-left` (default), `top`, `top-right`, `left`, `center`, `right`,
  `bottom-left`, `bottom`, `bottom-right`
- `offset_x`, `offset_y`: percentage or pixel metrics that may be negative. Default `"0px"`.
- `screen`: optional display name, as shown in System Settings → Displays

Placement is resolved against the screen's visible frame, which excludes the menu bar and the Dock.
Offsets are applied to the position and the result is clipped to the visible frame, so a `100%`
width with `offset_x = "20px"` yields the shifted visible area rather than overflowing the screen.

The screen is chosen in this order: the display named by `screen`, else the display under the mouse
cursor, else the display of the active window. If the named display is not connected, the fallback
is used. A size that resolves larger than the visible frame is an error.

Apps with a minimum window size may not fit the requested rectangle exactly; quartz-drop logs when the
final frame differs from the request.

## Differences from plasma-drop

Existing plasma-drop configs load as-is. Options that do not apply on macOS are ignored, never
errors. They are reported as "ignored on macOS" notes, separate from warnings: logged at info level,
printed by `quartz-drop check` as `ignored on macOS: ...` lines, and listed in Settings → General
under a collapsed "Ignored on macOS (N)" group.

| Key                      | Why it is ignored                                                              |
| ------------------------ | ------------------------------------------------------------------------------ |
| `hide_decorations`       | macOS public APIs cannot change other apps' title bars                         |
| `follow_current_desktop` | Moving windows between Spaces is impossible since macOS 14.5; use the app's Dock menu: Options → Assign To → All Desktops |
| `[app.animation]` with `style` other than `none` | Animation is not implemented yet |
| `hotkey` using `f21`-`f24` | macOS supports `f1`-`f20`; that app is skipped with an "ignored on macOS" note |
| `working_directory` that does not exist on this Mac | A relative path is still an error, as in plasma-drop |

`[app.animation]` is parsed and validated exactly like plasma-drop, so invalid values are errors:

| Key             | Values                                         | Default |
| --------------- | ---------------------------------------------- | ------- |
| `style`         | `none`, `slide`, `fade`, `slide-fade`          | `none`  |
| `easing`        | `linear`, `ease-out`, `ease-in-out`            |         |
| `duration_ms`   | 0 to 2000                                      | `150`   |
| `frame_delay_ms`| greater than 0                                 | `16`    |

Other differences:

- `bundle_id` is new and is the most reliable way to match and start an app.
- The default `hide_behavior` is `hide`; plasma-drop defaults to `offscreen`. Explicit values work
  in both.
- `offscreen` leaves a 1px sliver in the bottom-right corner of the right-most display.
- Placement uses the visible frame instead of the full screen.
- Native full-screen apps cannot be overlaid.
- `screen` takes a display name instead of a KWin output name such as `eDP-1`; a name that is not
  connected falls back to the screen under the cursor.
- Linux executable paths such as `/usr/bin/dolphin` load, but launching fails at toggle time unless
  the path exists on macOS. Matching by `filename` uses the basename against the app name and
  executable name.
- `process_name` matches the bundle ID, app name, and executable name instead of KWin identity fields.

## Using a plasma-drop config

A plasma-drop `config.toml` can be copied to `~/.config/quartz-drop/config.toml` and loads
unchanged (plasma-drop's `resources/example-config.toml` does). Options that do not apply on macOS
are ignored, never errors. Then:

1. Run `quartz-drop check` (binary at `QuartzDrop.app/Contents/MacOS/quartz-drop`). It prints
   `ignored on macOS: ...` lines for the options that have no effect.
2. Adjust `filename` / `bundle_id` to macOS apps. A Linux path such as `/usr/bin/dolphin` loads, but
   launching fails at toggle time unless that path exists on macOS. Matching by `filename` uses the
   basename (`dolphin`) against the app name and executable name.
3. Set `hide_behavior` explicitly if you rely on the plasma-drop default (`offscreen`); quartz-drop
   defaults to `hide`.

## Validation

Errors stop the load (and a running instance keeps its previous config). Common ones:

- no `[[app]]` entry
- empty, over-long, or duplicate `name`; duplicate hotkeys
- unknown hotkey modifier or key
- none of `bundle_id`, `filename`, `process_name`, `window_title` set
- invalid `attach_mode`, `hide_behavior`, `position`, or regex
- malformed metric (use `50%` or `640px`), non-positive size, or percentage size over 100
- both `command` and `arguments` set
- invalid `[app.animation]` value
- relative `working_directory`

## Complete Example

See [resources/example-config.toml](../resources/example-config.toml), or print it with
`quartz-drop print-example-config`.
