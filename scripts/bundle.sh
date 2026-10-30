#!/bin/zsh
# Builds Jharokha and wraps it into build/Jharokha.app, plus build/Jharokha.dmg and .zip.
# Env: VERSION=1.0.0 sets the app version; UNIVERSAL=1 builds for Apple silicon + Intel.
# Signs with $SIGN_IDENTITY, else the local "Pane Local Signing" certificate when the
# keychain has it, else ad-hoc. A stable identity keeps the Accessibility grant across
# rebuilds; ad-hoc signing makes macOS ask again after every build.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
VERSION="${VERSION:-1.0.0}"

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    # One build per architecture, joined with lipo: works with just the Command Line Tools.
    for arch in arm64 x86_64; do
        swift build -c "$CONFIG" --product Jharokha --triple "$arch-apple-macosx15.0"
    done
    BIN="build/Jharokha-universal"
    mkdir -p build
    lipo -create ".build/arm64-apple-macosx/$CONFIG/Jharokha" ".build/x86_64-apple-macosx/$CONFIG/Jharokha" -output "$BIN"
else
    swift build -c "$CONFIG" --product Jharokha
    BIN="$(swift build -c "$CONFIG" --show-bin-path)/Jharokha"
fi

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

# Downloads: a zip, and a disk image with a shortcut to Applications to drag onto.
rm -f build/Jharokha.zip build/Jharokha.dmg
ditto -c -k --keepParent "$APP" build/Jharokha.zip
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Jharokha" -srcfolder "$STAGE" -ov -format UDZO build/Jharokha.dmg
rm -rf "$STAGE"
lipo -archs "$APP/Contents/MacOS/Jharokha" | sed 's/^/Architectures: /'
echo "Built build/Jharokha.dmg and build/Jharokha.zip (v$VERSION)"
