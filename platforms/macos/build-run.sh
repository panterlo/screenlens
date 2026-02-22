#!/bin/bash
set -e

cd "$(dirname "$0")"

APP="ScreenLens.app"
BINARY="$APP/Contents/MacOS/ScreenLens"

echo "Building..."
swift build

echo "Packaging into $APP..."
cp .build/debug/ScreenLens "$BINARY"
codesign --force --sign - "$APP"

echo "Launching..."
open "$APP"
