# quartz-drop

<p align="center">
  <img src="resources/icons/quartz-drop.svg" alt="quartz-drop icon" width="128" height="128">
</p>

[![CI](https://github.com/SkeLLLa/quartz-drop/actions/workflows/ci.yml/badge.svg)](https://github.com/SkeLLLa/quartz-drop/actions/workflows/ci.yml)
[![Release](https://github.com/SkeLLLa/quartz-drop/actions/workflows/release.yml/badge.svg)](https://github.com/SkeLLLa/quartz-drop/actions/workflows/release.yml)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](COPYING)

`quartz-drop` is a macOS dropdown app launcher. It registers global hotkeys, finds or starts the
apps you configure, and moves their windows onto a portion of the screen, such as the left half.
It talks to the window server (Quartz Compositor, the macOS counterpart of KWin) through the
Accessibility API.

Think Yakuake-style dropdown behavior, but for Terminal, Finder, Safari, or any other app you add
to the config. It runs in the background with an optional menu bar icon and is configured with
TOML.

It is a port of [plasma-drop](https://github.com/SkeLLLa/plasma-drop), the KDE Plasma 6 version,
and accepts the same config format with a few documented differences.

> [!NOTE]
> quartz-drop was converted from [plasma-drop](https://github.com/SkeLLLa/plasma-drop) (Rust, KDE
> Plasma) to Swift and macOS with AI assistance.

## Install and First Run

Requires macOS 13 (Ventura) or newer and Accessibility permission. Download a universal build from
the [latest release](https://github.com/SkeLLLa/quartz-drop/releases/latest) or build from source
with `mise run bundle-universal`, copy `QuartzDrop.app` to `/Applications`, and open it. See
[Getting started](docs/getting-started.md) for installation, signing and quarantine notes,
permissions, the first-run flow, the menu bar menu, and the command line.

## Configure Apps

Configuration is TOML. Each `[[app]]` entry defines one managed app, its hotkey, how to find or
launch it, and where to place it.

```toml
[[app]]
name = "finder"
hotkey = "ctrl+alt+f"
bundle_id = "com.apple.finder"
attach_mode = "find-or-start"
hide_behavior = "minimize"
hide_on_focus_lost = true

[app.placement]
width = "50%"
height = "100%"
position = "left"
```

Common fields:

| Field                | Purpose                                                                |
| -------------------- | ---------------------------------------------------------------------- |
| `name`               | Unique app identifier                                                  |
| `hotkey`             | Global shortcut, for example `ctrl+alt+f`                              |
| `bundle_id`          | Bundle identifier used to match and start the app                      |
| `filename`           | App name or path (`/Applications/Safari.app`) matcher and launcher     |
| `command`            | Explicit launch command array                                          |
| `arguments`          | Arguments for the launch built from `filename` (not with `command`)    |
| `process_name`       | Regex matched against bundle ID, app name, and executable name         |
| `window_title`       | Regex matched against the window title                                 |
| `attach_mode`        | `find` or `find-or-start` (default)                                    |
| `hide_behavior`      | `hide` (default), `minimize`, or `offscreen`                           |
| `hide_on_focus_lost` | Hide after focus moves to another window                               |
| `[app.placement]`    | Width, height, position, offsets, and target screen                    |

Behavior in short:

- Only one managed app is visible at a time; showing one hides the others.
- Pressing the hotkey of a visible but unfocused app brings it forward instead of hiding it.
- With `find-or-start`, a missing app is launched and quartz-drop waits up to about 20 seconds for
  its window.
- Placement uses the screen's visible frame, which excludes the menu bar and Dock.
- Original window frames are restored when quit, including on Ctrl-C and SIGTERM.
- Apps with a minimum window size may not fit the requested rectangle exactly; this is logged.

See [resources/example-config.toml](resources/example-config.toml) for a complete example and
[docs/configuration.md](docs/configuration.md) for every option.

## Differences from plasma-drop

Existing plasma-drop configs load unchanged; options that do not apply on macOS are ignored, never
errors. The main differences are the new `bundle_id` key, a default `hide_behavior` of `hide`, and
display-name based `screen`. See [Differences from plasma-drop](docs/configuration.md#differences-from-plasma-drop)
and [Using a plasma-drop config](docs/configuration.md#using-a-plasma-drop-config).

## Alternatives

- [Hammerspoon](https://www.hammerspoon.org): scriptable in Lua, can do all of this with code
- [Rectangle](https://rectangleapp.com): window layout only, no app toggling
- [Thor](https://github.com/gbammc/Thor) and [rcmd](https://lowtechguys.com/rcmd/): hotkeys to
  switch apps, no placement
- iTerm2 hotkey window: dropdown behavior for a single app

## Documentation

- [Getting started](docs/getting-started.md)
- [Configuration](docs/configuration.md)
- [Distribution](docs/distribution.md)
- [Development](docs/development.md)
- [Documentation index](docs/index.md)

## Development

```bash
mise run check   # what CI runs: swift format lint, jactionlint, shellcheck, build, tests
mise run fmt     # format Swift sources
mise run run     # run from the build directory with -v
mise tasks       # list all tasks
```

The mise tasks wrap the Makefile targets of the same name. CI installs the same tools with
`jdx/mise-action`, and `mise.lock` pins their download URLs and checksums. See
[docs/development.md](docs/development.md) for details and
[docs/distribution.md](docs/distribution.md) for releases.

Version bumps, changelog updates, tags, and GitHub releases are managed by release-please from
Conventional Commit messages; do not edit `CHANGELOG.md` by hand.

## Support

If `quartz-drop` is useful to you and you want to say thanks, please consider supporting Ukrainian
defenders instead of sending money to the author.

[![Come Back Alive](resources/badges/donate-come-back-alive.svg)](https://savelife.in.ua/en/donate-en/)
[![Sternenko Fund](resources/badges/donate-sternenko-fund.svg)](https://www.sternenkofund.org/en/donate)
[![Prytula Foundation](resources/badges/donate-prytula-foundation.svg)](https://prytulafoundation.org/en/donation)

The same links are in the menu bar menu and in Settings → General.

## License

GPL-3.0-or-later. See [COPYING](COPYING).
