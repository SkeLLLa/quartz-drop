# Development

## Setup

Tools are pinned with [mise](https://mise.jdx.dev) in `mise.toml` and `mise.lock`:

| Tool        | Version | Notes                                                  |
| ----------- | ------- | ------------------------------------------------------ |
| swift       | 6.4.0   | swift.org toolchain; includes `swift format`           |
| jactionlint | 1.8.2   | jdx's maintained actionlint fork                       |
| shellcheck  | 0.11.0  |                                                        |

The macOS SDK comes from the Xcode Command Line Tools (or Xcode).

```bash
mise trust
mise bootstrap --only tools,task
```

The `bootstrap` task checks that the Command Line Tools are installed (it starts the installer if
not), prints the Swift version, and runs `swift package resolve`. Plain `mise bootstrap` also
applies your global `[bootstrap]` config.

## Tasks

Each mise task wraps the Makefile target of the same name, so `make <target>` works without mise
(using the `swift` on `PATH`). Run `mise tasks` or `make help` for the list. `mise run check` is
what CI runs; the workflows are in `.github/workflows`.

## Project structure

- `Sources/QuartzDropCore/`: pure logic (config, hotkeys, placement, matching, the toggle state
  machine). No AppKit, ApplicationServices, or Carbon; unit-tested.
- `Sources/QuartzDrop/`: the executable target, the AppKit, Accessibility, and Carbon glue plus
  the menu bar and SwiftUI Settings UI.
- `Tests/QuartzDropCoreTests/`: Swift Testing (`import Testing`, `@Test`, `#expect`), one suite per
  Core file.
- `resources/`: `example-config.toml`, `icons/`, `badges/`.
- `packaging/Info.plist` and `scripts/bundle.sh`: bundle template and the script that builds and
  signs the app bundle.

`Sources/QuartzDropCore/ExampleConfig.swift` is a hand-kept mirror of
`resources/example-config.toml` (there is no generator); `ExampleConfigTests` fails when they
differ, so update both together.

## Formatting

`swift format` (configured in `.swift-format`) formats `Sources`, `Tests`, and `Package.swift`.
Run `mise run fmt` to apply it; `mise run lint` checks it strictly.

## Releasing

Releases use [release-please](https://github.com/googleapis/release-please) (config in
`release-please-config.json`, manifest in `.release-please-manifest.json`):

1. Use Conventional Commits (`feat:`, `fix:`, ...) on pull requests to `master`.
2. On every push to `master`, `release.yml` runs release-please, which opens or updates a release
   pull request that bumps `version.txt` and `Sources/QuartzDrop/Version.swift` (the line marked
   `// x-release-please-version`) and writes `CHANGELOG.md`. Do not edit those by hand.
3. Merging the release pull request creates the tag and GitHub release. The `build` job then builds
   the universal app, optionally signs and notarizes it, and attaches the artifacts; see
   [Distribution](distribution.md).

Optional signing secrets (all repository secrets; signing is skipped when
`MACOS_CERTIFICATE_P12` is empty):

| Secret                       | Purpose                                             |
| ---------------------------- | --------------------------------------------------- |
| `MACOS_CERTIFICATE_P12`      | Base64 Developer ID Application certificate (.p12)  |
| `MACOS_CERTIFICATE_PASSWORD` | Password of the .p12                                |
| `MACOS_SIGNING_IDENTITY`     | Signing identity, passed as `CODESIGN_IDENTITY`     |
| `APPLE_ID`                   | Apple ID for notarization                           |
| `APPLE_TEAM_ID`              | Team ID for notarization                            |
| `APPLE_APP_PASSWORD`         | App-specific password for notarization              |

Notarization runs only when all six are set.
