#!/bin/sh
# Regenerates the README images in docs/images from the real views and demo data.
set -e
cd "$(dirname "$0")/.."
swift build -c release
BIN=.build/release/Greenlight
"$BIN" --screenshots docs/images
"$BIN" --iconset build/icon
cp build/icon/icon_256x256@2x.png docs/images/icon.png
