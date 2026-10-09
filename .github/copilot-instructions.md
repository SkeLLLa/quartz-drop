# GitHub Copilot Review Instructions

When reviewing this repository, treat it as a production Swift 6 macOS menu-bar app.
Prioritize correctness, user safety, concurrency soundness, and maintainability over stylistic churn.

Project context:
- The package is `quartz-drop` (app bundle `QuartzDrop.app`), a macOS port of the Rust KDE app `plasma-drop`.
- It toggles windows (dropdown style) via global hotkeys.
- `Sources/QuartzDropCore` holds pure, testable logic (config, window matching, geometry, hotkey parsing). It must not import AppKit, ApplicationServices, or Carbon.
- `Sources/QuartzDrop` holds the AppKit, Accessibility (AX) and Carbon hotkey glue plus the menu-bar UI.
- `Tests/` uses Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- Version lives in `version.txt` and `Sources/QuartzDrop/Version.swift` (line marked `// x-release-please-version`); release-please updates both. Do not suggest hand-editing them or `CHANGELOG.md`.
- Tools are pinned in `mise.toml`/`mise.lock` (Swift, jactionlint, shellcheck) and installed in CI by `jdx/mise-action`. The primary local validation command is `mise run check` (= `make check`: swift format lint, jactionlint, shellcheck, swift build, swift test). App bundles are built by `scripts/bundle.sh`.
- `resources/example-config.toml` is mirrored in `Sources/QuartzDropCore/ExampleConfig.swift` (`ExampleConfigTests` checks they match). Config keys and menu contents are documented in `README.md` and `docs/`; keep them in sync with code changes (including the Support Ukraine links in `SupportLinks.swift`).
- Animations are not supported; `[app.animation]` is validated like plasma-drop and ignored. Options that do not apply on macOS are "ignored on macOS" notes, never errors.

Conventions:
- Swift 6 language mode with strict concurrency. Flag data races, missing `Sendable`, and `@unchecked Sendable` or `nonisolated(unsafe)` without justification.
- UI, AX, and hotkey-callback code belongs on `@MainActor`; check actor hops at Carbon/C callback boundaries.
- Formatting is enforced by `swift format`; do not comment on style it already decides.
- Commits and PR titles follow Conventional Commits (`feat:`, `fix:`, `chore:` ...); release notes are generated from them.
- Prefer small, directly relevant suggestions. Do not request broad refactors unless they remove a concrete bug or maintenance risk.

macOS limitations to respect (do not suggest code that assumes otherwise):
- Other apps' window opacity and decorations cannot be controlled.
- Windows cannot be moved across Spaces via public APIs.
- Accessibility permission is tied to the app's code signature; ad-hoc rebuilds can invalidate the grant. Changes to signing or bundle identifiers affect users' permissions.

Review focus:
- Behavior regressions in window matching, AX calls (check `AXError` handling and nil results), hotkey registration/unregistration, config loading, and app lifecycle.
- Config changes must stay backward compatible or include clear migration behavior.
- Release workflow changes: universal (arm64 + x86_64) bundle, code signing/notarization paths, checksums, and provenance attestation must stay consistent.
- Core logic changes should come with Swift Testing coverage in `Tests/`.

Expected validation:
- For Swift source or manifest changes, expect `make check`.
- For documentation-only changes, expect at least spelling/link review and no broken references.
- For bundle or release workflow changes, expect `ARCHS=universal scripts/bundle.sh` plus `lipo -archs` and `codesign --verify` checks where practical.

Comment style:
- Lead with concrete bugs, security issues, regressions, or missing tests.
- Include file and line references when possible.
- Explain the user-visible impact and the smallest practical fix.
- Avoid comments that only restate the code or enforce personal style preferences.
