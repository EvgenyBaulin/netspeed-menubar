#!/bin/zsh
# Compiles the String Catalog (Localization/Localizable.xcstrings) into
# per-language .lproj/Localizable.strings under the target's Resources.
#
# Command-line SwiftPM copies .xcstrings verbatim instead of compiling it
# (catalog compilation is an Xcode build-system feature), so the generated
# .strings files are committed; re-run this script after editing the catalog.
# Requires Xcode (xcstringstool).
set -euo pipefail

cd "$(dirname "$0")/.."

TOOL="$(xcrun -f xcstringstool 2>/dev/null || true)"
if [ -z "$TOOL" ] && [ -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcstringstool ]; then
    TOOL=/Applications/Xcode.app/Contents/Developer/usr/bin/xcstringstool
fi
if [ -z "$TOOL" ]; then
    echo "error: xcstringstool not found (install Xcode)" >&2
    exit 1
fi

"$TOOL" compile Localization/Localizable.xcstrings \
    --output-directory Sources/NetSpeedMenuBar/Resources

echo "Generated:"
ls -d Sources/NetSpeedMenuBar/Resources/*.lproj
