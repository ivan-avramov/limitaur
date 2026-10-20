#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
APP="${1:-dist/Limitaur.app}"
if [ "$#" -gt 0 ]; then shift; fi
swift build -c release "$@"
BIN_DIR="$(swift build -c release "$@" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Limitaur" "$APP/Contents/MacOS/Limitaur"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist" | grep -qx true
test -x "$APP/Contents/MacOS/Limitaur"
codesign --force --sign - "$APP"
echo "$APP"
