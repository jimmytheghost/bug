#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OUTPUT_DIR=${1:-"$PROJECT_ROOT/dist"}
APP_DIR="$OUTPUT_DIR/Bug.app"

if [ ! -f "$PROJECT_ROOT/Resources/Encoder/libmp3lame.dylib" ]; then
    bash "$SCRIPT_DIR/prepare-encoder.sh"
fi
swift build --package-path "$PROJECT_ROOT" -c release
BIN_DIR=$(swift build --package-path "$PROJECT_ROOT" -c release --show-bin-path)
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"
cp "$BIN_DIR/Bug" "$APP_DIR/Contents/MacOS/Bug"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_ROOT/Resources/Encoder/libmp3lame.dylib" "$APP_DIR/Contents/Frameworks/libmp3lame.dylib"
mkdir -p "$APP_DIR/Contents/Resources/Encoder"
cp "$PROJECT_ROOT/Resources/Encoder/COPYING.LAME" "$PROJECT_ROOT/Resources/Encoder/lame-3.100.tar.gz" "$APP_DIR/Contents/Resources/Encoder/"
cp "$PROJECT_ROOT/THIRD_PARTY_NOTICES.md" "$SCRIPT_DIR/prepare-encoder.sh" "$APP_DIR/Contents/Resources/Encoder/"
codesign --force --sign - "$APP_DIR/Contents/Frameworks/libmp3lame.dylib"
if [ -f "$PROJECT_ROOT/Resources/Bug.icns" ]; then
    cp "$PROJECT_ROOT/Resources/Bug.icns" "$APP_DIR/Contents/Resources/Bug.icns"
fi
chmod 755 "$APP_DIR/Contents/MacOS/Bug"
codesign --force --sign - "$APP_DIR"
printf 'Packaged %s\n' "$APP_DIR"
