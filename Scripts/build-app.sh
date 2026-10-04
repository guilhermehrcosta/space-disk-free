#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Space Disk Free"
EXECUTABLE="SpaceDiskFree"
APP_DIR="build/${APP_NAME}.app"
ARCHS="${ARCHS:-$(uname -m)}"

SWIFT_FLAGS=(-c release)
if [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
    SWIFT_FLAGS+=(--build-system native)
fi

SLICES_DIR="$(mktemp -d)"
trap 'rm -rf "$SLICES_DIR"' EXIT
for arch in $ARCHS; do
    swift build "${SWIFT_FLAGS[@]}" --arch "$arch"
    cp "$(swift build "${SWIFT_FLAGS[@]}" --arch "$arch" --show-bin-path)/$EXECUTABLE" "$SLICES_DIR/$arch"
done

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
lipo -create "$SLICES_DIR"/* -output "$APP_DIR/Contents/MacOS/$EXECUTABLE"

PLIST="$APP_DIR/Contents/Info.plist"
cp Resources/Info.plist "$PLIST"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
[[ -n "${VERSION:-}" ]] && plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
[[ -n "${BUILD_NUMBER:-}" ]] && plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$PLIST"
plutil -lint "$PLIST" >/dev/null

codesign --force --sign - --timestamp=none "$APP_DIR"

echo "✓ $APP_DIR ($(lipo -archs "$APP_DIR/Contents/MacOS/$EXECUTABLE"))"
