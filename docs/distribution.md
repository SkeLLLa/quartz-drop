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
| `CODESIGN_IDENTITY` | empty     | SHA-1 of a code-signing certificate; empty signs ad hoc      |
| `BUILD_ONLY`        | empty     | `1`: stop after building `.build/bundle/quartz-drop`         |
| `SKIP_BUILD`        | empty     | `1`: package that binary instead of building                 |
| `QUARTZ_DROP_COMMIT` | git `HEAD` | Commit shown in About (`-dirty` with local changes)        |
| `SOURCE_DATE_EPOCH` | now       | Build date shown in About                                    |

The script:

1. Builds each architecture in its own scratch path, `.build/bundle-<arch>`, because the swift.org
   toolchain would otherwise put every `--arch` build in one products directory, then combines
   them with `lipo` into `.build/bundle/quartz-drop` and strips debug and local symbols.
   `BUILD_ONLY=1` stops here; `SKIP_BUILD=1` starts from that binary (it must hold exactly the
   requested architectures).
2. Assembles `QuartzDrop.app` with `packaging/Info.plist` (version from `version.txt`).
3. Builds `AppIcon.icns` from `resources/icons/quartz-drop-1024.png`.
4. Signs with the hardened runtime: ad hoc by default; with `CODESIGN_IDENTITY` it writes the
   designated requirement `identifier "ua.SkeLLLa.QuartzDrop" and certificate leaf = H"<sha1>"`
   and fails unless the signature satisfies it (see [Signing](#signing)).
5. Writes `quartz-drop-<version>-macos-<arch>.zip` (`<arch>` is `universal`, `arm64`, or `x86_64`)
   without extended attributes, so the archive holds no AppleDouble `._*` files.

Universal builds need the swift.org toolchain from mise; the Command Line Tools' own Swift lacks
the x86_64 compatibility libraries.

## Signing

The app is signed with quartz-drop's own self-signed code-signing certificate. There is no Apple
Developer ID: the project is open source and non-profit, so releases are not notarized and a
browser download still needs `xattr -dr com.apple.quarantine /Applications/QuartzDrop.app` once.
What the certificate buys is a stable designated requirement:

```text
designated => identifier "ua.SkeLLLa.QuartzDrop" and certificate leaf = H"<sha1>"
```

macOS keys the Accessibility grant (and launch at login) to this requirement, so it survives
updates. An ad-hoc signature pins the cdhash instead, and every build looks like a new app. The
first signed release still looks new to a copy that was ad-hoc signed, so the grant is asked
for once more.

The certificate is quartz-drop's alone. cAInary and local dev builds each use their own, and the
requirement pins the exact leaf, so a key leaked from one can't sign as another.

**Pin.** `packaging/signing/release.sha1` holds the certificate's SHA-1. It is the `codesign`
identity and the pin `bundle.sh` checks. Once the pin is committed, the release fails rather than
ship ad hoc or with another key; until then it signs ad hoc, emits a CI warning and says so in the
release notes. Changing the pin makes every user grant Accessibility again, so do it only when the
certificate expires (it is valid for 20 years) or leaks.

**Secrets.** The key lives only in the `macos-signing` GitHub environment, used by the `build`
job of `release.yml`:

| Secret                       | Value                                              |
| ---------------------------- | -------------------------------------------------- |
| `MACOS_CERTIFICATE_P12`      | the .p12 (key and certificate), base64 on one line |
| `MACOS_CERTIFICATE_PASSWORD` | its password                                       |

Create the environment before the secrets, in **Settings → Environments → New environment**
`macos-signing` (a workflow that names a missing environment creates it without any rules):

- **Deployment branches and tags:** *Selected branches and tags*, with only `master`. A
  workflow on any other branch or tag that names the environment is refused before it runs.
  Repository secrets have no such rule, so don't keep these as repository secrets.
- **Required reviewers** (optional): yourself, if every release should wait for approval.
- No environment variables are needed; the identity comes from the committed pin.

`ci.yml` never names the environment, and pull requests (including from forks) build ad hoc.
The release compiles the binary before the key is imported, then puts the .p12 into a temporary
keychain that only `/usr/bin/codesign` may use, checks that it holds the pinned identity, signs,
and deletes the keychain.

**Making the certificate.** On the maintainer's Mac (not in CI), with the `macos-signing-cert`
script from the maintainer's dotfiles, or the same steps by hand: an RSA 3072 self-signed
certificate named `ua.SkeLLLa.QuartzDrop`, organization `github.com/SkeLLLa/quartz-drop`, with
critical `keyUsage = digitalSignature` and `extendedKeyUsage = codeSigning`, exported with
`/usr/bin/openssl` (LibreSSL; the PKCS#12 that OpenSSL 3 writes by default doesn't import).

```bash
macos-signing-cert -g SkeLLLa/quartz-drop ua.SkeLLLa.QuartzDrop
mkdir -p packaging/signing
cp ~/.local/share/macos-signing/ua.SkeLLLa.QuartzDrop.release/*.sha1 packaging/signing/release.sha1
```

`-g` sets both secrets in the `macos-signing` environment through `gh`. Then back up the .p12
and its password outside the machine and delete the directory.

**Local builds.** Make a separate dev certificate and import it into the login keychain, so dev
builds keep the Accessibility grant across rebuilds without ever matching the release requirement:

```bash
macos-signing-cert -d -i ua.SkeLLLa.QuartzDrop
CODESIGN_IDENTITY="$(cat ~/.local/share/macos-signing/ua.SkeLLLa.QuartzDrop.dev/*.sha1)" make bundle
codesign -d -r- dist/QuartzDrop.app
```

## Release artifacts

`release.yml` runs on pushes to `master`; see [Development](development.md#releasing) for how the
version is computed. When there is something to release, it builds and checks everything first;
only then does the `publish` job commit the version bump, tag it, and create the GitHub release
with, for version `<version>`:

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

The signer pin `ps1_3lbhdizx3fdmmm5ki37kzixcwy` identifies the release workflow and is the same for every release.
`verify-packslip` checks the published manifest against the `PACKSLIP_PIN` repository variable and
prints the pin to its job summary.

`packaging/mise-registry/quartz-drop.toml` is a staged entry for the mise registry, so that
`mise use quartz-drop` works without the `packslip:` prefix. mise doesn't read it from here; it goes
into a jdx/mise PR once quartz-drop meets mise's bar for new tools.

## Verifying a download

```bash
shasum -a 256 -c quartz-drop-<version>-macos-universal.zip.sha256
shasum -a 256 -c SHA256SUMS --ignore-missing
gh attestation verify quartz-drop-<version>-macos-universal.zip --repo SkeLLLa/quartz-drop
```

To verify the packslip manifest:

```bash
packslip verify packslip.sigstore.json --pin ps1_3lbhdizx3fdmmm5ki37kzixcwy --artifact quartz-drop-<version>-macos-universal.tar.gz
```

## CI

Every action is pinned to a full commit SHA, with the version in a comment; Dependabot bumps
both, and waits a week after an action or package release (`cooldown`) so a compromised one has
time to be pulled. `scripts/check-action-pins.sh` fails on any `uses:` that isn't pinned
(`make lint-pins` runs it and its tests). Both workflows default to `permissions: {}`, each job
asks for what it needs and has a timeout, and only the `publish` job keeps a checkout token.

- `ci.yml`: commit message check on pull requests; `pin-check`; `actions-lint` (jactionlint,
  version from `mise.toml`, downloaded and checked against its checksum and build provenance; it
  runs shellcheck on every `run:` script); `make check`; and a universal bundle smoke test that
  builds and bundles in the release's two steps, checks both architectures with `lipo -archs`,
  verifies the signature, and runs `--version`.
- `release.yml`, on pushes to `master` without `[skip ci]`:
  - `pin-gate`: fetches every workflow at the pushed commit and fails unless all actions are
    pinned. Every other job waits for it.
  - `quality`: `mise run check` on macOS.
  - `prepare`: git-cliff computes the version, the release notes and `CHANGELOG.md`. Nothing is
    committed yet.
  - `build` (environment `macos-signing`): applies the version locally
    (`scripts/set-version.sh`), builds the universal binary, then imports the key and signs (see
    [Signing](#signing)), and keeps the zip and tar.gz as artifacts.
  - `checksums`: `.sha256` files, `SHA256SUMS` and the build provenance attestation, after
    `quality` and `build`.
  - `publish`: commits the bump to `master` as `github-actions[bot]` (no force push, so it fails
    if `master` moved), tags it, and creates the GitHub release with the assets. If a run fails
    after tagging, re-running it finishes the same release.
  - `packslip`, `publish-packslip`, `verify-packslip`: sign the packslip manifest, upload
    `packslip.sigstore.json` to the release, and verify the published files.
