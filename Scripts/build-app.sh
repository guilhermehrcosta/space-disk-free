#!/usr/bin/env bash
# Compila em release e monta "build/Space Disk Free.app" (assinatura ad-hoc).
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Space Disk Free"
EXECUTABLE="SpaceDiskFree"
APP_DIR="build/${APP_NAME}.app"
# O backend padrão do SwiftPM (Swift Build) não inicializa só com as Command Line Tools.
SWIFT_FLAGS=(-c release --build-system native)

swift build "${SWIFT_FLAGS[@]}"
BIN_DIR="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null

codesign --force --sign - --timestamp=none "$APP_DIR"

echo "✓ $APP_DIR"
