#!/bin/zsh
# Builds Pane and wraps it into build/Pane.app.
# Signs with $SIGN_IDENTITY when set; otherwise ad-hoc, which means macOS asks for
# Accessibility access again after every rebuild.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
VERSION="${VERSION:-0.1.0}"

swift build -c "$CONFIG" --product Pane
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Pane"

APP="build/Pane.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pane"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.pane.Pane</string>
    <key>CFBundleName</key><string>Pane</string>
    <key>CFBundleDisplayName</key><string>Pane</string>
    <key>CFBundleExecutable</key><string>Pane</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Pane — automatic window tiling for macOS</string>
</dict>
</plist>
PLIST

codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $PWD/$APP"
