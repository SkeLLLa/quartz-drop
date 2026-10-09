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
2. Combines them with `lipo`, strips debug and local symbols, and assembles `QuartzDrop.app` with `packaging/Info.plist`
   (version from `version.txt`).
3. Builds `AppIcon.icns` from `resources/icons/quartz-drop-1024.png`.
4. Signs: ad-hoc with `-`, otherwise with the hardened runtime and a timestamp, then verifies.
5. Writes `quartz-drop-<version>-macos-<arch>.zip` (`<arch>` is `universal`, `arm64`, or `x86_64`)
   without extended attributes, so the archive holds no AppleDouble `._*` files.

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

`release.yml` runs on pushes to `master`; see [Development](development.md#releasing) for how the
version is computed. When there is something to release, the `release` job commits the version
bump, tags it, and creates the GitHub release. The `build` job then publishes, for version
`<version>`:

- `quartz-drop-<version>-macos-universal.zip`
- `quartz-drop-<version>-macos-universal.tar.gz` (contains `QuartzDrop.app`)
- a `.sha256` file for each archive
- `SHA256SUMS` covering both archives
- `packslip.sigstore.json`, a signed packslip manifest for the tar.gz

Both archives carry a GitHub build provenance attestation.

The packslip manifest is signed keylessly through GitHub OIDC. It records the tar.gz as os
`darwin` with no architecture (universal), the command `quartz-drop` as
`QuartzDrop.app/Contents/MacOS/quartz-drop`, and a resource `app` as `QuartzDrop.app`. This is
what `mise use -g packslip:github.com/SkeLLLa/quartz-drop` and `packslip install` use.

The signer pin (`ps1_...`) identifies the release workflow and is the same for every release. It
is not known until the first release: `verify-packslip` prints it to the job summary, then the
maintainer sets the `PACKSLIP_PIN` repository variable and adds the pin to the README.

## Verifying a download

```bash
shasum -a 256 -c quartz-drop-<version>-macos-universal.zip.sha256
shasum -a 256 -c SHA256SUMS --ignore-missing
gh attestation verify quartz-drop-<version>-macos-universal.zip --repo SkeLLLa/quartz-drop
```

To verify the packslip manifest (add `--pin ps1_...` once the README lists the signer pin):

```bash
packslip verify packslip.sigstore.json --artifact quartz-drop-<version>-macos-universal.tar.gz
```

## CI

- `ci.yml`: commit message check on pull requests, `make check`, and a universal bundle smoke test (`make bundle-universal`)
  that checks both architectures with `lipo -archs`, verifies the signature, and runs
  `--version`.
- `release.yml`, on pushes to `master` without `[skip ci]`:
  - `quality`: `mise run check` on macOS.
  - `release`: git-cliff computes the version, updates `CHANGELOG.md`, `version.txt` and
    `Version.swift`, commits as `github-actions[bot]`, tags, and creates the GitHub release.
  - `build`: universal bundle, optional signing and notarization, archives, checksums,
    attestation, upload.
  - `packslip`, `publish-packslip`, `verify-packslip`: sign the packslip manifest, upload
    `packslip.sigstore.json` to the release, and verify the published files.

Both install tools with `jdx/mise-action@v5`.
