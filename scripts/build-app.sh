#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache dist
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache"
APP="$PWD/dist/forget it.app"
if [ "${1:-}" = "--preview" ]; then APP="$PWD/dist/preview/forget it Preview.app"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ForgetIt "$APP/Contents/MacOS/ForgetIt"
cp packaging/Info.plist "$APP/Contents/Info.plist"
if [ -f packaging/AppIcon.icns ]; then
    cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIconV2.icns"
    # Replace the original filename too: older Finder/Launch Services entries may still reference it.
    cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
if [ "${1:-}" = "--preview" ]; then
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier app.forgetit.preview' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleName forget it Preview' "$APP/Contents/Info.plist"
fi
codesign --force --deep --sign - "$APP"
touch "$APP/Contents" "$APP"
echo "Built: $APP"
if [ "${1:-}" = "--dmg" ]; then
    STAGE=$(mktemp -d /tmp/forget-it-dmg.XXXXXX)
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "forget it" -srcfolder "$STAGE" -ov -format UDZO "$PWD/dist/forget-it.dmg"
fi
