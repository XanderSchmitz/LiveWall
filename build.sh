#!/bin/bash
# Builds LiveWall.app — requires Xcode Command Line Tools (xcode-select --install)
set -e
cd "$(dirname "$0")"

echo "▸ Building LiveWall (release)…"
swift build -c release 2>&1 | tail -5

APP="build/LiveWall.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp .build/release/LiveWall "$APP/Contents/MacOS/LiveWall"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Embed Sparkle.framework (auto-updates) and point the binary at it
cp -R .build/release/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/LiveWall"

# Ad-hoc codesign so macOS lets it run locally — sign the embedded framework
# (and its nested XPC services/helper) before the outer app bundle.
codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --deep --sign - "$APP"

echo "✓ Built $APP"
echo "  Run it:      open $APP"
echo "  Install it:  cp -r $APP /Applications/"
