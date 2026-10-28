#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_NAME="HSBG Mac Overlay.app"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
APP_DIR="$OUTPUT_DIR/$APP_NAME"

# UNIVERSAL=1 builds for both Apple silicon and Intel (used for releases).
if [ "${UNIVERSAL:-0}" = 1 ]; then
    set -- -c release --arch arm64 --arch x86_64
else
    set -- -c release
fi

cd "$PROJECT_DIR"
swift build "$@"
BIN_DIR=$(swift build "$@" --show-bin-path)
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/HSBGMacOverlay" "$APP_DIR/Contents/MacOS/HSBGMacOverlay"
cp "$PROJECT_DIR/packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --sign - --entitlements "$PROJECT_DIR/packaging/HSBGMacOverlay.entitlements" "$APP_DIR"

echo "Packaged: $APP_DIR"
