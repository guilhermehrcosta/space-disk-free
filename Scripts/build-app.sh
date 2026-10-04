#!/usr/bin/env bash
# Compila em release e monta "build/Space Disk Free.app" (assinatura ad-hoc).
#
# Variáveis opcionais:
#   ARCHS="arm64 x86_64"  arquiteturas do binário (padrão: só a da máquina)
#   VERSION=1.2.0         CFBundleShortVersionString (padrão: o do Info.plist)
#   BUILD_NUMBER=42       CFBundleVersion (padrão: o do Info.plist)
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Space Disk Free"
EXECUTABLE="SpaceDiskFree"
APP_DIR="build/${APP_NAME}.app"
ARCHS="${ARCHS:-$(uname -m)}"

SWIFT_FLAGS=(-c release)
# Só com as Command Line Tools o backend padrão do SwiftPM (Swift Build) não inicializa.
if [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
    SWIFT_FLAGS+=(--build-system native)
fi

# Compila cada arquitetura separadamente e junta com lipo (funciona com ou sem Xcode).
# Cada binário é copiado na hora: com o Xcode, todas as arquiteturas saem na mesma pasta.
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
