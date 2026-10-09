#!/usr/bin/env bash
# Render the PNG artwork from the SVG sources in resources/. Needs resvg (`mise run artwork`
# provides it). Commit the PNGs; the bundle build uses them and does not need resvg.
set -euo pipefail

cd "$(dirname "$0")/.."

resvg -w 1024 -h 1024 resources/icons/quartz-drop.svg resources/icons/quartz-drop-1024.png
resvg -w 1280 -h 640 --resources-dir resources/social \
    resources/social/github-social-preview.svg resources/social/github-social-preview.png
