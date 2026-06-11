#!/bin/zsh
# Builds a release binary and assembles a standalone NetSpeed.app bundle.
# Ad-hoc signed — fine for local use; replace `-s -` with your Developer ID
# to distribute.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release
BINDIR="$(swift build -c release --show-bin-path)"

# Assemble outside iCloud (like .build): the file provider re-adds xattrs to
# synced files, which breaks strict codesign verification. `dist` in the
# project root is a symlink to this folder.
DIST="$HOME/Library/Developer/netspeed-menubar-build/dist"
mkdir -p "$DIST"
ln -sfn "$DIST" dist
rm -rf "$DIST/NetSpeedMac.app" # bundle name before v1.3

APP="$DIST/NetSpeed.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINDIR/NetSpeedMenuBar" "$APP/Contents/MacOS/NetSpeed"
cp scripts/Info.plist "$APP/Contents/Info.plist"

# Copy SwiftPM resource bundles (localization lives in Bundle.module) into
# Contents/Resources so strings resolve inside the .app as well.
for bundle in "$BINDIR"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# App icon: images/icon.png (1024×1024 PNG with alpha) → AppIcon.icns.
if [ -f images/icon.png ]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" images/icon.png \
            --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
        double=$((size * 2))
        sips -z "$double" "$double" images/icon.png \
            --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    echo "Icon: images/icon.png → AppIcon.icns"
else
    echo "Note: images/icon.png not found — building without an app icon."
fi

xattr -cr "$APP"
codesign --force -s - "$APP"

echo "Built $APP (symlinked as $PWD/dist/NetSpeed.app)"
