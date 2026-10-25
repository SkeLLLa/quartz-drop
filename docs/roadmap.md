# Roadmap

Planned work. Contributions are welcome: open issues and pull requests at
https://github.com/SkeLLLa/quartz-drop, follow Conventional Commits, and see
[development.md](development.md) for the setup and the checks.

## TODO

### Features

- [ ] **Window animations.** `[app.animation]` is parsed and validated like plasma-drop, but
  `style` values other than `none` (`slide`, `fade`, `slide-fade`) are ignored on macOS today.
  Implement slide and fade with `easing`, `duration_ms` and `frame_delay_ms`.
- [ ] **Per-Space handling.** Public APIs cannot move windows between Spaces, so
  `follow_current_desktop` is ignored. Investigate detecting a window on another Space and
  reporting it, or bringing the user to it, instead of failing silently.
- [ ] **Native full-screen apps.** Apps in native full-screen cannot be overlaid. Detect them and
  report it, or leave full-screen before placing the window.
- [ ] **Offscreen sliver.** `hide_behavior = "offscreen"` leaves a 1px sliver in the bottom-right
  corner of the right-most display. Find a placement that avoids it.

### Distribution

- [ ] **Homebrew cask.** Publish a cask in a `SkeLLLa/homebrew-tap` tap, bumped by the release
  workflow.
- [ ] **Separate arm64 and x86_64 archives**, if there is demand for smaller downloads.
- [ ] **DMG.** Ship a disk image with an Applications shortcut next to the zip and tar.gz.
- [ ] **mise registry listing**, so `mise use quartz-drop` works without the `packslip:` backend
  prefix. The entry is staged in `packaging/mise-registry/quartz-drop.toml`.
- [ ] **MacPorts and Nix (nix-darwin) packages.**
