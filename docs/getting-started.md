# Getting Started

## Requirements

- macOS 13 (Ventura) or newer
- Accessibility permission, used to move, resize, focus, and minimize other apps' windows

Hotkeys use Carbon `RegisterEventHotKey`, so no Input Monitoring permission is needed.

## Install from a release

1. Download the zip or tar.gz from the
   [latest release](https://github.com/SkeLLLa/quartz-drop/releases/latest). Archives are universal
   (Apple silicon and Intel).
2. Verify it (see [Distribution](distribution.md#verifying-a-download)).
3. Copy `QuartzDrop.app` to `/Applications`.
4. If the release is not notarized, clear the quarantine flag once:

   ```bash
   xattr -dr com.apple.quarantine /Applications/QuartzDrop.app
   ```

Releases are signed with a Developer ID and notarized only when the maintainers' signing secrets
are configured; otherwise they are ad-hoc signed. An ad-hoc signed release is still quarantined
when downloaded, so step 4 applies to it.

## Install from source

Tools are pinned in `mise.toml` and `mise.lock`. The macOS SDK comes from the Xcode Command Line
Tools; full Xcode is not required.

```bash
mise trust
mise bootstrap --only tools,task   # install tools, check the CLT, run `swift package resolve`
mise run bundle-universal          # dist/QuartzDrop.app (arm64 + x86_64)
cp -R dist/QuartzDrop.app /Applications/
```

Use `mise run bundle` for a build of the host architecture only. Plain `mise bootstrap` also works
but additionally applies the `[bootstrap]` section of your global mise config. Without mise, the
Makefile targets use whatever `swift` is on `PATH`; universal builds need the swift.org toolchain
because the Command Line Tools' own Swift lacks x86_64 compatibility libraries.

Set `CODESIGN_IDENTITY` to sign with a Developer ID instead of an ad-hoc signature; see
[Distribution](distribution.md).

## Permissions

Grant Accessibility under System Settings → Privacy & Security → Accessibility. On launch,
quartz-drop asks for it when it is missing; the menu bar menu shows "Grant Accessibility Access…"
and Settings → Permissions shows the status until it is granted.

macOS ties the permission to the code signature. Ad-hoc signed and self-built binaries get a new
signature on every rebuild, so remove `QuartzDrop` from the Accessibility list and add it again
after each rebuild. A stable Developer ID signature avoids this.

## First run

Open `QuartzDrop.app`. If `~/.config/quartz-drop/config.toml` does not exist, it is created from
the example config and Settings opens. Settings also opens when the config has an error, or when
the menu bar icon is disabled and Accessibility is not granted.

Settings has three tabs:

- **General**: config file location and reload, launch at login, a Menu Bar section ("Show menu bar
  icon", written to the config file in place, keeping comments), the Support Ukraine links, and a
  collapsed "Ignored on macOS (N)" group when the config has options that do not apply on macOS
- **Apps**: the configured apps and their hotkeys, with Show/Hide buttons and a per-app error
  indicator when an app fails to toggle
- **Permissions**: Accessibility status and a shortcut to the right System Settings pane

Edit the config (Settings → General → Open, or the menu bar menu → Open Config). The file reloads
automatically when it changes (in-place saves, symlinked configs, and replacing the config
directory are all handled); Reload Config forces it. Errors keep the previous config running.

The menu bar menu lists, in order: one item per app (`name`, then its hotkey; a checkmark means
visible, click toggles it; a failing app is marked with a warning icon and a tooltip with the
error), Settings… (⌘,), Open Config, Reload Config (⌘R), a Support Ukraine submenu, Hide Menu Bar
Icon (asks for confirmation), and Quit (⌘Q). It also shows a Grant Accessibility Access… item while
the permission is missing and a config error item when the config is invalid.

The app has no Dock icon. Hide Menu Bar Icon sets `menu_bar = false`. Launch the app a second time
while it is running (or run `open -a QuartzDrop`) and the running instance opens Settings, where
you can turn the icon back on. Launch at login (Settings → General) uses `SMAppService` and is
available when running as a `.app` bundle; macOS may ask you to approve it under System Settings →
General → Login Items.

### Command line

```bash
quartz-drop init [--force]       # write the example config to the config path
quartz-drop print-example-config # print the example config
quartz-drop check                # validate the config and exit
quartz-drop --config PATH        # use another config file (relative and ~ paths work)
quartz-drop -v                   # log at info; -vv for debug
quartz-drop --log-level trace    # error | warn | info | debug | trace | off
quartz-drop --version
```

The binary is `QuartzDrop.app/Contents/MacOS/quartz-drop`. Closing the terminal it runs in
(SIGHUP), Ctrl-C, or SIGTERM quits cleanly and restores window frames.

### Logging

The default level is `error`. Use `-v` (info), `-vv` (debug), `--log-level`, the config
`log_level`, or the `QUARTZ_DROP_LOG` environment variable (which overrides everything else); see
[Configuration](configuration.md#top-level-fields). Logs go to the unified log:

```bash
log stream --predicate 'subsystem == "ua.SkeLLLa.QuartzDrop"'
```

Running the binary from a terminal also prints them to stderr.

## Hotkey conflicts

A global hotkey does nothing if macOS already uses the combination. Pick unused ones, or disable
the system shortcut in System Settings → Keyboard → Keyboard Shortcuts:

- `cmd+f5` toggles VoiceOver. Disable it if you use it.
- ``cmd+grave`` is "Move focus to next window" and must be disabled if you use it.
- `cmd+f1` toggles display mirroring on Apple keyboards.
- Function keys need System Settings → Keyboard → "Use F1, F2, etc. keys as standard function
  keys", or must be pressed together with `fn`.

Hotkeys such as `ctrl+alt+f` avoid most conflicts.

## Typical session

1. The config is loaded and validated.
2. One global hotkey is registered per app.
3. A hotkey press finds an existing window or launches the app, then moves it into the configured
   rectangle and focuses it. Pressing it again hides it.
4. Quitting restores original window frames.

See [resources/example-config.toml](../resources/example-config.toml) for a starter config.
