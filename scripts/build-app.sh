#!/bin/sh
# Builds a universal GitHub Greenlight.app (Apple silicon + Intel) into build/.
#   scripts/build-app.sh            build only
#   scripts/build-app.sh --install  also copy to ~/Applications and launch
#   scripts/build-app.sh --zip      also make build/GitHub-Greenlight.zip for a GitHub release
set -e
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
APP="build/GitHub Greenlight.app"

echo "Building Greenlight $VERSION"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Greenlight"

rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Greenlight"

"$BIN" --iconset build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.vincent-caetano.greenlight</string>
  <key>CFBundleName</key><string>Greenlight</string>
  <key>CFBundleDisplayName</key><string>GitHub Greenlight</string>
  <key>CFBundleExecutable</key><string>Greenlight</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict></plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

case "$1" in
  --install)
    mkdir -p "$HOME/Applications"
    pkill -x Greenlight 2>/dev/null || true
    rm -rf "$HOME/Applications/GitHub Greenlight.app"
    cp -R "$APP" "$HOME/Applications/"
    open "$HOME/Applications/GitHub Greenlight.app"
    echo "Installed to ~/Applications/GitHub Greenlight.app"
    ;;
  --zip)
    rm -f build/GitHub-Greenlight.zip
    ditto -c -k --keepParent "$APP" build/GitHub-Greenlight.zip
    echo "Packed build/GitHub-Greenlight.zip"
    ;;
esac
