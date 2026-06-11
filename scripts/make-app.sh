#!/bin/zsh
# Builds a release binary and assembles a standalone NetSpeedMac.app bundle
# in dist/. Ad-hoc signed — fine for local use; replace `-s -` with your
# Developer ID to distribute.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/NetSpeedMenuBar"

# Assemble outside iCloud (like .build): the file provider re-adds xattrs to
# synced files, which breaks strict codesign verification. `dist` in the
# project root is a symlink to this folder.
DIST="$HOME/Library/Developer/netspeed-menubar-build/dist"
mkdir -p "$DIST"
ln -sfn "$DIST" dist

APP="$DIST/NetSpeedMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/NetSpeedMac"
cp scripts/Info.plist "$APP/Contents/Info.plist"

xattr -cr "$APP"
codesign --force -s - "$APP"

echo "Built $APP (symlinked as $PWD/dist/NetSpeedMac.app)"
