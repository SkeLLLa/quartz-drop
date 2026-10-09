# quartz-drop setup guide for AI agents

Instructions for an AI coding agent that installs and configures quartz-drop for a user. A person
who wants to read about quartz-drop should start with [`README.md`](README.md); the full option
reference is [`docs/configuration.md`](docs/configuration.md). Contributors to this repository
should read [`docs/development.md`](docs/development.md) and
[`.github/copilot-instructions.md`](.github/copilot-instructions.md) instead.

## What you are setting up

- `QuartzDrop.app` is a macOS dropdown app launcher (a Swift port of plasma-drop). It is an agent
  app: a menu bar icon, no Dock icon. One global hotkey per configured app shows, places and
  focuses that app's window; pressing it again hides it.
- The CLI is `quartz-drop`, which is `QuartzDrop.app/Contents/MacOS/quartz-drop`. Running it with
  no subcommand starts the app. Subcommands and flags: `init [--force]`, `print-example-config`,
  `check`, `--config PATH`, `-v` / `-vv`, `--log-level LEVEL`, `--version`.
- The config is `~/.config/quartz-drop/config.toml` (override with `--config PATH`). It reloads
  automatically when it changes; errors keep the previous config running.

## Ground rules

1. **Ask before you change anything.** Describe the plan (apps, hotkeys, placement, install
   method) and get the user's agreement first.
2. **Back up the config before editing it**, e.g. `cp ~/.config/quartz-drop/config.toml
   ~/.config/quartz-drop/config.toml.bak-$(date +%s)`. Edit in place; don't regenerate the file.
3. **Don't invent config keys.** Use only the keys in [the schema](#config-schema) below.
   `docs/configuration.md` lists the validation errors that stop a load (bad hotkey, duplicate
   `name`, no matcher, invalid enum value, malformed metric, ...). An unknown or misspelled key is
   silently ignored and `quartz-drop check` still passes, so a typo goes unnoticed: compare every
   key you write against the schema.
4. **Always run `quartz-drop check` after editing** and fix every error before moving on.
5. **You cannot grant Accessibility permission.** The user must do it in System Settings →
   Privacy & Security → Accessibility.
6. **Never run `xattr -dr com.apple.quarantine` or `tccutil` without asking.** Explain what the
   command does first.
7. **Don't pick hotkeys that clash with system shortcuts**: `cmd+f5` (VoiceOver), `cmd+grave`
   (move focus to next window), `cmd+f1` (display mirroring), and bare function keys unless the
   user has enabled "Use F1, F2, etc. keys as standard function keys". `ctrl+alt+<letter>` avoids
   most conflicts.

## Step 1: Inspect the environment

```sh
sw_vers -productVersion                    # must be 13 (Ventura) or newer
uname -m                                   # arm64 / x86_64 (release builds are universal)
command -v quartz-drop mise packslip gh
ls -d /Applications/QuartzDrop.app
ls -l ~/.config/quartz-drop/config.toml    # existing quartz-drop config
ls -l ~/.config/plasma-drop/config.toml    # existing plasma-drop config to migrate (path may vary)
```

If `QuartzDrop.app` or `quartz-drop` already exists, skip step 2. `quartz-drop --version` prints
the version.

## Step 2: Install

Pick the first method that applies and that the user is happy with. Homebrew is not available.

| Condition | Command |
| --- | --- |
| User wants the app in `/Applications` (default) | release download, see below |
| `mise` 2026.9.2+ present | `mise use -g packslip:github.com/SkeLLLa/quartz-drop` |
| `packslip` 1.5.1+ present | `packslip install github.com/SkeLLLa/quartz-drop` |
| Swift toolchain via mise, user wants a build | `mise trust && mise bootstrap --only tools,task && mise run bundle-universal` |

**Release download:**

```sh
dir=$(mktemp -d) && cd "$dir"
gh release download --repo SkeLLLa/quartz-drop --pattern 'quartz-drop-*-macos-universal.zip'
# without gh: curl -LO from https://github.com/SkeLLLa/quartz-drop/releases/latest
unzip quartz-drop-*-macos-universal.zip
mv QuartzDrop.app /Applications/
```

Verification steps (checksums, `gh attestation verify`) are in
[`docs/distribution.md`](docs/distribution.md#verifying-a-download). A browser-downloaded release
may be quarantined; if macOS blocks the app, ask the user before running
`xattr -dr com.apple.quarantine /Applications/QuartzDrop.app` (releases that are not notarized
need it once).

**mise / packslip:** both verify the signed manifest and put only the `quartz-drop` command (the
executable inside the bundle) on `PATH`; running `quartz-drop` starts the app. They do not copy
`QuartzDrop.app` to `/Applications`. The signer `--pin` identifies the release workflow, not a
version. It will be published in [`README.md`](README.md) after the first release: add
`--pin <value>` if `README.md` shows one, and never guess it.

**From source:** after `mise run bundle-universal` the app is `dist/QuartzDrop.app`; copy it with
`cp -R dist/QuartzDrop.app /Applications/`. `mise run bundle` builds the host architecture only.

Confirm with `command -v quartz-drop` (mise/packslip) or `ls -d /Applications/QuartzDrop.app`.
If the command is not found, the install's bin directory isn't on `PATH`; tell the user rather
than editing their shell profile unasked. For an app-only install, call the binary as
`/Applications/QuartzDrop.app/Contents/MacOS/quartz-drop`.

## Step 3: Build the config from the user's wishes

If no config exists, `quartz-drop init` writes the example config (`--force` overwrites, so never
use it on an existing file). Ask the user, per app: which app, which hotkey, and where the window
should go (side, size, display).

Find a bundle ID (the most reliable way to match and start an app):

```sh
osascript -e 'id of app "Safari"'
mdls -name kMDItemCFBundleIdentifier -r /Applications/Safari.app
```

Minimal valid entry:

```toml
[[app]]
name = "notes"
hotkey = "ctrl+alt+n"
bundle_id = "com.apple.Notes"
hide_behavior = "minimize"
hide_on_focus_lost = true

[app.placement]
width = "50%"
height = "100%"
position = "right"
```

For `screen`, the docs only say it is a display name as shown in System Settings → Displays; if
it isn't connected, the display under the cursor is used. Omit it unless the user wants a fixed
display. `quartz-drop print-example-config` prints a larger starter file.

## Config schema

Top level (optional): `log_level` (`error` default, `warn`, `info`, `debug`, `trace`, `off`) and
`menu_bar` (bool, default `true`). The only table is `[[app]]`, with an optional `[app.placement]`.

`[[app]]`:

| Key | Values |
| --- | --- |
| `name` | required, unique, at most 64 characters |
| `hotkey` | required, e.g. `ctrl+alt+f`; unique across apps |
| `bundle_id` | e.g. `com.apple.Terminal`; matches and can launch the app |
| `filename` | app name (`Safari`) or path (`/Applications/Safari.app`, or an executable) |
| `process_name` | case-insensitive regex on bundle ID, app name, executable name |
| `window_title` | case-insensitive regex on the window title |
| `command` | spawn argv array, e.g. `["/usr/bin/open", "-a", "Notes"]` |
| `arguments` | string array for `filename`/`bundle_id` launches; not with `command` |
| `attach_mode` | `find`, `find-or-start` (default) |
| `working_directory` | absolute path; relative is an error, missing directory is ignored |
| `hide_behavior` | `hide` (default), `minimize`, `offscreen` |
| `hide_on_focus_lost` | bool, default `false` |

At least one of `bundle_id`, `filename`, `process_name`, `window_title` is required.

Hotkeys: zero or more modifiers plus one key, joined with `+`, each modifier at most once.
Modifiers: `ctrl`/`control`, `shift`, `alt`/`option`/`opt`, `cmd`/`command`/`super`/`meta`/`win`.
Keys: `a`-`z`, `0`-`9`, `f1`-`f20`, `grave`, `section`, `space`, `tab`, `return`, `escape`,
`delete`, `forwarddelete`, punctuation names (`minus`, `equal`, `bracketleft`, `bracketright`,
`semicolon`, `quote`, `backslash`, `comma`, `period`, `slash`), and `left`, `right`, `up`,
`down`, `home`, `end`, `pageup`, `pagedown`. On ISO keyboards the key below Esc is `section`.

`[app.placement]`:

| Key | Values |
| --- | --- |
| `width`, `height` | `"50%"` or `"640px"`, default `"100%"`, positive, percentages at most 100 |
| `position` | `top-left` (default), `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, `bottom-right` |
| `offset_x`, `offset_y` | percentage or pixel metric, may be negative, default `"0px"` |
| `screen` | display name from System Settings → Displays |

`[app.animation]` exists for plasma-drop compatibility (`style` other than `none` is ignored on
macOS); don't add it for new configs.

## Step 4: Migrate a plasma-drop config (only if the user has one)

A plasma-drop `config.toml` can be copied to `~/.config/quartz-drop/config.toml` and loads
unchanged. Options that don't apply on macOS are ignored, never errors.

1. Run `quartz-drop check`. It prints `ignored on macOS: ...` lines for options with no effect
   (`hide_decorations`, `follow_current_desktop`, animation styles, `f21`-`f24` hotkeys,
   `working_directory` paths that don't exist on this Mac).
2. Replace Linux `filename` paths (`/usr/bin/dolphin`) with macOS `bundle_id` or `filename`
   values; they load but fail at toggle time.
3. Set `hide_behavior` explicitly if the user relies on plasma-drop's default (`offscreen`);
   quartz-drop defaults to `hide`.
4. `screen` takes a display name, not a KWin output such as `eDP-1`.

## Step 5: Validate and start

```sh
quartz-drop check                  # validates the config and exits; also prints warnings and notes
open -a QuartzDrop                 # or: open /Applications/QuartzDrop.app
```

1. If the config does not exist, the app creates it from the example and opens Settings.
2. Ask the user to grant Accessibility (System Settings → Privacy & Security → Accessibility);
   the app prompts for it on launch, and Settings → Permissions shows the status.
3. Ask the user to press a configured hotkey and confirm the window appears and is placed.
4. For logs, run `quartz-drop -v` from a terminal, or
   `log stream --predicate 'subsystem == "ua.SkeLLLa.QuartzDrop"'` (default level is `error`;
   `QUARTZ_DROP_LOG` overrides everything).
5. Launch at login is Settings → General, a user action; macOS may ask them to approve it under
   System Settings → General → Login Items.

Config edits apply automatically; Reload Config (⌘R in the menu bar menu) forces it.

## Troubleshooting

- **Hotkey does nothing:** it probably clashes with a system shortcut (see the ground rules), the
  config has an error (`quartz-drop check`), or an f-key is being used without `fn`. Try
  `ctrl+alt+<letter>`.
- **Window isn't moved or resized:** Accessibility is missing. Ad-hoc signed and self-built
  copies get a new signature on every rebuild or update, so the user must remove `QuartzDrop`
  from the Accessibility list and add it again. Fixed-size windows are moved but not resized.
- **App not found or not started:** set `bundle_id` (the most reliable matcher), and check
  `attach_mode` (`find` never launches). `find-or-start` without `command`, `bundle_id` or
  `filename` can only attach to a running window.
- **Full-screen apps** (native macOS full screen) can't be overlaid.
- **Option has no effect:** it may be on the "ignored on macOS" list (`quartz-drop check`, or
  Settings → General → "Ignored on macOS").
- **Menu bar icon is gone:** `menu_bar = false`. Run `open -a QuartzDrop` to open Settings and
  turn it back on.
- **A config error appears in the menu or Settings:** the previous config is still running; fix
  the file, and it reloads on save.
