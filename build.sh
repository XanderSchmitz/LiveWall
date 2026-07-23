#!/bin/bash
# Builds LiveWall.app — requires Xcode Command Line Tools (xcode-select --install)
set -e
cd "$(dirname "$0")"

echo "▸ Building LiveWall (release)…"
swift build -c release 2>&1 | tail -5

APP="build/LiveWall.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/LiveWall "$APP/Contents/MacOS/LiveWall"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc codesign so macOS lets it run locally
codesign --force --deep --sign - "$APP"

echo "✓ Built $APP"
echo "  Run it:      open $APP"
echo "  Install it:  cp -r $APP /Applications/"
