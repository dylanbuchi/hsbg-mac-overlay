#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_NAME="HSBG Mac Overlay.app"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
APP_DIR="$OUTPUT_DIR/$APP_NAME"

cd "$PROJECT_DIR"
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/HSBGMacOverlay" "$APP_DIR/Contents/MacOS/HSBGMacOverlay"
cp "$PROJECT_DIR/packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --sign - --entitlements "$PROJECT_DIR/packaging/HSBGMacOverlay.entitlements" "$APP_DIR"

echo "Packaged: $APP_DIR"
