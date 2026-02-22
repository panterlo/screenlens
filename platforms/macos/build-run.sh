#!/bin/bash
set -e

cd "$(dirname "$0")"

APP="ScreenLens.app"
BINARY="$APP/Contents/MacOS/ScreenLens"

# Kill any running instance first
pkill -9 -x ScreenLens 2>/dev/null || true
sleep 1

echo "Building..."
swift build

echo "Packaging into $APP..."
cp .build/debug/ScreenLens "$BINARY"
codesign --force --sign "ScreenLens Dev" "$APP"

echo "Launching..."
open -n "$APP"
