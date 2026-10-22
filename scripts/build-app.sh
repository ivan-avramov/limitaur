#!/bin/sh
# Builds a local ad-hoc signed Limitaur.app. Usage: build-app.sh [OUTPUT_APP] [swift build options...]
# The version comes from Sources/Limitaur/AppVersion.swift; the build number is the git commit count.
set -eu
cd "$(dirname "$0")/.."
APP="${1:-dist/Limitaur.app}"
if [ "$#" -gt 0 ]; then shift; fi
VERSION="$(sed -n 's/^    static let string = "\([^"]*\)"$/\1/p' Sources/Limitaur/AppVersion.swift)"
test -n "$VERSION" || { echo "build-app.sh: could not read version from AppVersion.swift" >&2; exit 1; }
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
REVISION="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
CORE="${VERSION%%-*}"; CORE="${CORE%%+*}"
if [ -n "$(git status --porcelain -- Package.swift Sources Resources scripts 2>/dev/null)" ]; then REVISION="$REVISION-dirty"; fi
swift build -c release "$@"
BIN_DIR="$(swift build -c release "$@" --show-bin-path)"
BUILT_VERSION="$("$BIN_DIR/Limitaur" --version)"
test "$BUILT_VERSION" = "$VERSION" || { echo "build-app.sh: binary reports $BUILT_VERSION, source says $VERSION" >&2; exit 1; }
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Limitaur" "$APP/Contents/MacOS/Limitaur"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Optional local provider glyph images (ignored by git): Resources/providers/<providerID>.png
/bin/rm -rf "$APP/Contents/Resources/providers"
if ls Resources/providers/*.png >/dev/null 2>&1; then
  mkdir -p "$APP/Contents/Resources/providers"
  cp Resources/providers/*.png "$APP/Contents/Resources/providers/"
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $CORE" \
                        -c "Set :CFBundleVersion $BUILD_NUMBER" \
                        -c "Add :LimitaurSourceRevision string $REVISION" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist" | grep -qx true
test -x "$APP/Contents/MacOS/Limitaur"
# Signing identity: LIMITAUR_SIGN_IDENTITY if set; otherwise a code-signing identity named
# "Limitaur Dev" when the login keychain has one; otherwise ad-hoc. A stable identity keeps the
# designated requirement the same across rebuilds, so the Keychain keeps trusting the app.
IDENTITY="${LIMITAUR_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q '"Limitaur Dev"'; then IDENTITY="Limitaur Dev"; fi
codesign --force --sign "${IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
(cd "$(dirname "$APP")" && shasum -a 256 "./$(basename "$APP")/Contents/MacOS/Limitaur" > "$(basename "$APP").sha256")
echo "$APP $VERSION ($BUILD_NUMBER, $REVISION, signed ${IDENTITY:-ad-hoc})"
