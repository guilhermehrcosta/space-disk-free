#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Space Disk Free"
APP_DIR="build/${APP_NAME}.app"
[[ -d "$APP_DIR" ]] || { echo "Rode Scripts/build-app.sh antes." >&2; exit 1; }

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP_DIR/Contents/Info.plist")"
DMG="build/SpaceDiskFree-${VERSION}.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
for attempt in 1 2 3; do
    if hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null; then
        echo "✓ $DMG"
        exit 0
    fi
    echo "hdiutil falhou (tentativa $attempt), tentando de novo…" >&2
    sleep 5
done
exit 1
