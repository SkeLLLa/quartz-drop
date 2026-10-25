#!/usr/bin/env bash
# Build QuartzDrop.app (and a distributable zip) from the SwiftPM package.
#
# Environment:
#   ARCHS              "universal" or "arm64 x86_64" for both; default: host arch
#   CONFIGURATION      SwiftPM configuration (default: release)
#   OUT_DIR            output directory (default: dist)
#   CODESIGN_IDENTITY  SHA-1 of a self-signed code-signing certificate in the keychain search
#                      list (default: empty, ad-hoc signature). See docs/distribution.md#signing.
#   BUILD_ONLY=1       stop after building .build/bundle/quartz-drop
#   SKIP_BUILD=1       package an earlier BUILD_ONLY binary instead of building. The release
#                      workflow builds first, so no package code runs while the key is imported.
#   QUARTZ_DROP_COMMIT commit for the About panel (default: git HEAD, -dirty with local changes)
#   SOURCE_DATE_EPOCH  build date for the About panel (default: now)
set -euo pipefail

cd "$(dirname "$0")/.."

ARCHS="${ARCHS:-$(uname -m)}"
CONFIGURATION="${CONFIGURATION:-release}"
OUT_DIR="${OUT_DIR:-dist}"

[ "$ARCHS" = "universal" ] && ARCHS="arm64 x86_64"
read -r -a arch_list <<< "$ARCHS"

VERSION="$(tr -d '[:space:]' < version.txt)"
if [ "${#arch_list[@]}" -gt 1 ]; then arch_label="universal"; else arch_label="${arch_list[0]}"; fi

BIN="$(pwd)/.build/bundle/quartz-drop"
APP="$OUT_DIR/QuartzDrop.app"
ZIP="$OUT_DIR/quartz-drop-$VERSION-macos-$arch_label.zip"

# --- 1. Build one binary per architecture, then combine ----------------------
if [ "${SKIP_BUILD:-}" = "1" ]; then
    # The earlier build must hold exactly the requested architectures.
    built="$(lipo -archs "$BIN" | tr ' ' '\n' | sort | xargs)"
    wanted="$(printf '%s\n' "${arch_list[@]}" | sort | xargs)"
    if [ "$built" != "$wanted" ]; then
        echo "error: $BIN has architectures '$built', expected '$wanted'" >&2
        exit 1
    fi
else
    binaries=()
    for arch in "${arch_list[@]}"; do
        # A scratch path per architecture: some toolchains (swift.org 6.4) put every --arch build
        # in the same products directory, so a shared one would leave only the last architecture.
        scratch=".build/bundle-$arch"
        echo "==> swift build -c $CONFIGURATION --arch $arch"
        swift build -c "$CONFIGURATION" --arch "$arch" --scratch-path "$scratch"
        bin_path="$(swift build -c "$CONFIGURATION" --arch "$arch" --scratch-path "$scratch" --show-bin-path)"
        binaries+=("$bin_path/quartz-drop")
    done
    mkdir -p "$(dirname "$BIN")"
    rm -f "$BIN"
    if [ "${#binaries[@]}" -gt 1 ]; then
        lipo -create "${binaries[@]}" -output "$BIN"
    else
        cp "${binaries[0]}" "$BIN"
    fi
    # Drop debug and local symbols; the release binary does not need them (about 40% smaller).
    strip -S -x "$BIN"
fi
if [ "${BUILD_ONLY:-}" = "1" ]; then
    echo "Binary: $BIN"
    exit 0
fi

# --- 2. Assemble the bundle -------------------------------------------------
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/quartz-drop"

COMMIT="${QUARTZ_DROP_COMMIT:-}"
if [ -z "$COMMIT" ]; then
    COMMIT="$(git rev-parse HEAD 2> /dev/null || echo unknown)"
    if [ -n "$(git status --porcelain 2> /dev/null)" ]; then COMMIT="$COMMIT-dirty"; fi
fi
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
    BUILD_DATE="$(date -u -r "$SOURCE_DATE_EPOCH" +%Y-%m-%dT%H:%M:%SZ)"
else
    BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi
sed -e "s/__VERSION__/$VERSION/g" -e "s/__COMMIT__/$COMMIT/g" -e "s/__BUILD_DATE__/$BUILD_DATE/g" \
    packaging/Info.plist > "$APP/Contents/Info.plist"
# GPL text ships with the app; the About panel points at it.
cp COPYING "$APP/Contents/Resources/COPYING"

# --- 3. Icon: PNG -> iconset -> icns ----------------------------------------
SRC_ICON="resources/icons/quartz-drop-1024.png"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SRC_ICON" --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$SRC_ICON" --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

# --- 4. Code signing --------------------------------------------------------
# A certificate signature makes the designated requirement `identifier … and certificate leaf =
# H"<sha1>"`, which stays the same across builds, so the Accessibility grant survives updates.
# An ad-hoc one pins the cdhash and changes with every build.
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
SIGN_ID="${CODESIGN_IDENTITY:-}"
if [ -n "$SIGN_ID" ]; then
    if ! printf '%s' "$SIGN_ID" | grep -Eq '^[0-9A-Fa-f]{40}$'; then
        echo "error: CODESIGN_IDENTITY must be the certificate's 40-digit SHA-1" >&2
        exit 1
    fi
    SIGN_ID="$(printf '%s' "$SIGN_ID" | tr '[:lower:]' '[:upper:]')"
    REQUIREMENT="identifier \"$BUNDLE_ID\" and certificate leaf = H\"$SIGN_ID\""
    # The requirement is spelled out rather than left to codesign's default, so it can't drift.
    codesign --force --options runtime --timestamp=none --sign "$SIGN_ID" -i "$BUNDLE_ID" \
        -r="designated => $REQUIREMENT" "$APP"
    codesign --verify --strict "$APP"
    # Fail unless both the signature and the designated requirement pin this identifier and leaf
    # (catches a wrong key, or a requirement that fell back to the cdhash).
    codesign --verify --strict -R="$REQUIREMENT" "$APP"
    codesign -d -r- "$APP" 2>&1 | grep -qiF "$REQUIREMENT" || {
        echo "error: the designated requirement of $APP does not pin leaf $SIGN_ID" >&2
        exit 1
    }
else
    codesign --force --options runtime --timestamp=none --sign - -i "$BUNDLE_ID" "$APP"
    codesign --verify --strict "$APP"
fi

# --- 5. Zip for distribution ------------------------------------------------
rm -f "$ZIP"
# --norsrc/--noextattr keep AppleDouble ._ files (quarantine, provenance) out of the archive.
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"

echo "App: $APP"
echo "Zip: $ZIP"
