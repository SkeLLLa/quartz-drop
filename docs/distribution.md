# Distribution

quartz-drop ships as a macOS app bundle, `QuartzDrop.app`, built from the SwiftPM package by
`scripts/bundle.sh`. The bundle is an agent app (`LSUIElement`, no Dock icon) and requires
macOS 13.

## Bundle script

```bash
scripts/bundle.sh                    # host architecture, ad-hoc signed
ARCHS=universal scripts/bundle.sh    # arm64 + x86_64
```

`make bundle` and `make bundle-universal` (or the mise tasks of the same name) wrap it.

| Variable            | Default   | Meaning                                                      |
| ------------------- | --------- | ------------------------------------------------------------ |
| `ARCHS`             | host arch | `universal`, or a space-separated list such as `arm64 x86_64` |
| `CONFIGURATION`     | `release` | SwiftPM configuration                                        |
| `OUT_DIR`           | `dist`    | Output directory                                             |
| `CODESIGN_IDENTITY` | `-`       | Signing identity; `-` is ad-hoc                              |

The script:

1. Builds each architecture in its own scratch path, `.build/bundle-<arch>`, because the swift.org
   toolchain would otherwise put every `--arch` build in one products directory.
2. Combines them with `lipo` and assembles `QuartzDrop.app` with `packaging/Info.plist`
   (version from `version.txt`).
3. Builds `AppIcon.icns` from `resources/icons/quartz-drop-512.png`.
4. Signs: ad-hoc with `-`, otherwise with the hardened runtime and a timestamp, then verifies.
5. Writes `quartz-drop-<version>-macos-<arch>.zip` (`<arch>` is `universal`, `arm64`, or `x86_64`).

Universal builds need the swift.org toolchain from mise; the Command Line Tools' own Swift lacks
the x86_64 compatibility libraries.

## Signing and notarization

An ad-hoc signed app runs, but Gatekeeper blocks a downloaded copy until the quarantine flag is
removed (`xattr -dr com.apple.quarantine QuartzDrop.app`), and macOS treats every rebuild as a new
app for the Accessibility permission. A Developer ID signature avoids both.

Locally:

```bash
CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ARCHS=universal scripts/bundle.sh
```

The release workflow runs `mise run check` first. It imports the certificate into a temporary keychain, builds with that identity,
then notarizes with `notarytool`, staples the ticket, and re-zips. It does this only when the
signing secrets are configured; see [Development](development.md#releasing) for the list. An
unsigned or un-notarized release emits a CI warning and adds a line to the release notes.

## Release artifacts

`release.yml` runs on pushes to `master`. After release-please creates a release, the `build` job
publishes, for version `<version>`:

- `quartz-drop-<version>-macos-universal.zip`
- `quartz-drop-<version>-macos-universal.tar.gz` (contains `QuartzDrop.app`)
- a `.sha256` file for each archive
- `SHA256SUMS` covering both archives

Both archives carry a GitHub build provenance attestation.

## Verifying a download

```bash
shasum -a 256 -c quartz-drop-<version>-macos-universal.zip.sha256
shasum -a 256 -c SHA256SUMS --ignore-missing
gh attestation verify quartz-drop-<version>-macos-universal.zip --repo SkeLLLa/quartz-drop
```

## CI

- `ci.yml`: commit message check on pull requests, `make check`, and a universal bundle smoke test (`make bundle-universal`)
  that checks both architectures with `lipo -archs`, verifies the signature, and runs
  `--version`.
- `release.yml`: release-please, then build, sign, notarize (optional), checksum, attest, and
  publish.

Both install tools with `jdx/mise-action@v5`.
