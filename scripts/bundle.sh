#!/bin/zsh
# Builds Jharokha (the Pane target) and wraps it into build/Jharokha.app.
# Signs with $SIGN_IDENTITY, else the local "Pane Local Signing" certificate when the
# keychain has it, else ad-hoc. A stable identity keeps the Accessibility grant across
# rebuilds; ad-hoc signing makes macOS ask again after every build.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
VERSION="${VERSION:-0.1.0}"

swift build -c "$CONFIG" --product Pane
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Pane"

APP="build/Jharokha.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Jharokha"
# Regenerate with: swift scripts/make-icon.swift
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- The identifier predates the name; changing it would reset Accessibility access and settings. -->
    <key>CFBundleIdentifier</key><string>dev.pane.Pane</string>
    <key>CFBundleName</key><string>Jharokha</string>
    <key>CFBundleDisplayName</key><string>Jharokha</string>
    <key>CFBundleExecutable</key><string>Jharokha</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Jharokha — automatic window tiling for macOS</string>
</dict>
</plist>
PLIST

IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]] && security find-identity -p codesigning | grep -q "Pane Local Signing"; then
    IDENTITY="Pane Local Signing"
fi
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"
echo "Signed with ${IDENTITY:-ad-hoc identity}"
echo "Built $PWD/$APP"
