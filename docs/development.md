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
- `resources/`: `example-config.toml`, `icons/`, `social/`, `badges/`.
- `packaging/Info.plist` and `scripts/bundle.sh`: bundle template and the script that builds and
  signs the app bundle.

`Sources/QuartzDropCore/ExampleConfig.swift` is a hand-kept mirror of
`resources/example-config.toml` (there is no generator); `ExampleConfigTests` fails when they
differ, so update both together.

## Formatting

`swift format` (configured in `.swift-format`) formats `Sources`, `Tests`, and `Package.swift`.
Run `mise run fmt` to apply it; `mise run lint` checks it strictly.

## Releasing

Releases are cut directly from `master` with [git-cliff](https://git-cliff.org) (config in
`cliff.toml`, pinned to 2.14.2 in the workflow). There is no release pull request.

1. Use Conventional Commits (`feat:`, `fix:`, ...) on pull requests to `master`.
2. On every push to `master` (except commits containing `[skip ci]`), `release.yml` runs the
   quality gate (`mise run check`), then the `release` job. git-cliff computes the next version
   from the commits since the last tag: the first release is `v0.1.0`, afterwards `feat` bumps the
   minor version and everything else bumps the patch. If there is nothing new, no release is made.
3. The job regenerates `CHANGELOG.md`, writes `version.txt` and `Sources/QuartzDrop/Version.swift`,
   commits `chore(release): vX [skip ci]` to `master` as `github-actions[bot]`, tags `vX`, and
   creates the GitHub release with the git-cliff notes. Do not edit those files by hand.
4. The `build` job builds the universal app, optionally signs and notarizes it, and attaches the
   artifacts. The `packslip`, `publish-packslip` and `verify-packslip` jobs sign and publish the
   packslip manifest; see [Distribution](distribution.md).

The workflow uses the default `GITHUB_TOKEN`: no PAT and no "Allow GitHub Actions to create pull
requests" setting. `master` must allow `github-actions[bot]` to push, so branch protection must
not block it.

Preview the next release locally:

```bash
mise x git-cliff@2.14.2 -- git cliff --bumped-version   # next version, for example v0.2.0
mise x git-cliff@2.14.2 -- git cliff --unreleased       # changelog entries for it
```

After the first release, `verify-packslip` prints the signer pin (`ps1_...`) to its job summary.
Set it as the repository variable `PACKSLIP_PIN` (Settings → Secrets and variables → Actions →
Variables) and add it to the README install table.

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

## Artwork

The icon is plasma-drop's raindrop terminal mark recolored as rose quartz, with crystal facets,
on a macOS app icon tile. The SVGs are the sources:

- `resources/icons/quartz-drop.svg`: app icon. `quartz-drop-1024.png` is rendered from it and
  `scripts/bundle.sh` builds `AppIcon.icns` from that PNG.
- `resources/social/github-social-preview.svg`: the repository social preview (upload
  `github-social-preview.png` under Settings → General → Social preview).
- The menu bar icon is drawn in code (`Sources/QuartzDrop/MenuBarIcon.swift`) as a template image
  from the same compact drop mark, so it needs no bundle resources.

After editing an SVG, run `mise run artwork` (it installs resvg) and commit the PNGs. The bundle
build only reads the PNG, so neither CI nor `make bundle` needs resvg.
