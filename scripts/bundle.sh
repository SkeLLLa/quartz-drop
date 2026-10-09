#!/usr/bin/env bash
# Build QuartzDrop.app (and a distributable zip) from the SwiftPM package.
#
# Environment:
#   ARCHS              "universal" or "arm64 x86_64" for both; default: host arch
#   CONFIGURATION      SwiftPM configuration (default: release)
#   OUT_DIR            output directory (default: dist)
#   CODESIGN_IDENTITY  signing identity; "-" = ad-hoc (default)
set -euo pipefail

cd "$(dirname "$0")/.."

ARCHS="${ARCHS:-$(uname -m)}"
CONFIGURATION="${CONFIGURATION:-release}"
OUT_DIR="${OUT_DIR:-dist}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

[ "$ARCHS" = "universal" ] && ARCHS="arm64 x86_64"
read -r -a arch_list <<< "$ARCHS"

VERSION="$(tr -d '[:space:]' < version.txt)"
if [ "${#arch_list[@]}" -gt 1 ]; then arch_label="universal"; else arch_label="${arch_list[0]}"; fi

APP="$OUT_DIR/QuartzDrop.app"
ZIP="$OUT_DIR/quartz-drop-$VERSION-macos-$arch_label.zip"

# --- 1. Build one binary per architecture -----------------------------------
binaries=()
for arch in "${arch_list[@]}"; do
    # A scratch path per architecture: some toolchains (swift.org 6.4) put every --arch build in
    # the same products directory, so a shared one would leave only the last architecture.
    scratch=".build/bundle-$arch"
    echo "==> swift build -c $CONFIGURATION --arch $arch"
    swift build -c "$CONFIGURATION" --arch "$arch" --scratch-path "$scratch"
    bin_path="$(swift build -c "$CONFIGURATION" --arch "$arch" --scratch-path "$scratch" --show-bin-path)"
    binaries+=("$bin_path/quartz-drop")
done

# --- 2. Assemble the bundle -------------------------------------------------
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "${#binaries[@]}" -gt 1 ]; then
    lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/quartz-drop"
else
    cp "${binaries[0]}" "$APP/Contents/MacOS/quartz-drop"
fi
# Drop debug and local symbols; the release binary does not need them (about 40% smaller).
strip -S -x "$APP/Contents/MacOS/quartz-drop"

sed "s/__VERSION__/$VERSION/g" packaging/Info.plist > "$APP/Contents/Info.plist"

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
if [ "$CODESIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

# --- 5. Zip for distribution ------------------------------------------------
rm -f "$ZIP"
# --norsrc/--noextattr keep AppleDouble ._ files (quarantine, provenance) out of the archive.
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"

echo "App: $APP"
echo "Zip: $ZIP"
