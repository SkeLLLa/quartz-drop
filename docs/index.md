# quartz-drop

<p align="center">
  <img src="../resources/icons/quartz-drop.svg" alt="quartz-drop icon" width="96" height="96">
</p>

`quartz-drop` is a macOS dropdown app launcher. It registers global hotkeys, finds or starts the
apps you configure, and moves their windows onto a portion of the screen through the Accessibility
API. It is a port of [plasma-drop](https://github.com/SkeLLLa/plasma-drop) and reads the same
TOML config format with a few documented differences.

## What It Does

- Loads a TOML config describing managed apps and reloads it when the file changes.
- Registers one global hotkey per app (Carbon `RegisterEventHotKey`, no Input Monitoring needed).
- Finds or launches matching windows and toggles them in and out of view.
- Shows only one managed app at a time.
- Runs in the background with an optional menu bar icon and a Settings window.
- Does not animate windows: `[app.animation]` is validated and ignored.
- Loads plasma-drop configs unchanged; options that do not apply on macOS are reported as "ignored on macOS" notes.

## Guide Pages

- [Getting started](getting-started.md): requirements, install, permissions, first run, hotkey
  conflicts.
- [Configuration](configuration.md): every config key, matching, hiding, and placement.
- [Development](development.md): mise setup, tasks, tests, project layout, releasing.
- [Distribution](distribution.md): bundle script, signing, notarization, release artifacts.

## Related Project

[plasma-drop](https://github.com/SkeLLLa/plasma-drop) is the KDE Plasma 6 version. Both are
inspired by [windows-terminal-quake](https://github.com/flyingpie/windows-terminal-quake).
