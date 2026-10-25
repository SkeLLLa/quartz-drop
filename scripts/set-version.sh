#!/bin/sh
# Write the release version into version.txt and Sources/QuartzDrop/Version.swift. Used by
# .github/workflows/release.yml: the build job applies it to a scratch checkout, and the publish
# job applies it again, commits and tags it.
#
# Usage: scripts/set-version.sh 1.2.3
set -eu

cd "$(dirname "$0")/.."

VERSION="${1:-}"
printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || {
    echo "usage: $0 MAJOR.MINOR.PATCH" >&2
    exit 2
}

echo "$VERSION" > version.txt
sed "s/^let appVersion = \".*\"/let appVersion = \"$VERSION\"/" Sources/QuartzDrop/Version.swift \
    > Sources/QuartzDrop/Version.swift.tmp
mv Sources/QuartzDrop/Version.swift.tmp Sources/QuartzDrop/Version.swift
grep -qF "let appVersion = \"$VERSION\"" Sources/QuartzDrop/Version.swift
echo "Version set to $VERSION"
