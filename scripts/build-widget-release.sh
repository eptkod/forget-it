#!/bin/bash
# Requires a real Developer ID Application identity for the supplied team.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${FORGETIT_SIGNING_IDENTITY:?Set FORGETIT_SIGNING_IDENTITY to your Developer ID Application identity}"
: "${FORGETIT_TEAM_ID:?Set FORGETIT_TEAM_ID to its ten-character Apple team ID}"
if [[ ! "$FORGETIT_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then echo "Invalid Apple team ID" >&2; exit 1; fi
mkdir -p .build
security find-identity -v -p codesigning > .build/signing-identities.txt
if ! grep -F -- "$FORGETIT_SIGNING_IDENTITY" .build/signing-identities.txt >/dev/null; then echo "Signing identity is not available in the keychain." >&2; exit 1; fi
bash scripts/build-app.sh
APP="$PWD/dist/forget it.app"
EXT="$APP/Contents/PlugIns/ForgetItWidget.appex"
GROUP="$FORGETIT_TEAM_ID.forgetit"
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
mkdir -p "$EXT/Contents/MacOS"
swiftc -O -swift-version 5 -D WIDGET_EXTENSION -parse-as-library -module-cache-path "$PWD/.build/module-cache" Sources/ForgetIt/ClockDisplay.swift Sources/ForgetIt/WidgetSnapshot.swift Widgets/ForgetItWidget/ForgetItWidget.swift -o "$EXT/Contents/MacOS/ForgetItWidget"
cat > "$EXT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.forgetit.planner.widget</string>
<key>CFBundleName</key><string>forget it Calendar</string>
<key>CFBundleExecutable</key><string>ForgetItWidget</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>CFBundleShortVersionString</key><string>0.3.1</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>PlannerAppGroup</key><string>$GROUP</string>
<key>NSExtension</key><dict><key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string></dict>
</dict></plist>
PLIST
cat > .build/widget.entitlements <<PLIST
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.application-groups</key><array><string>$GROUP</string></array>
</dict></plist>
PLIST
cat > .build/planner.entitlements <<PLIST
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>com.apple.security.application-groups</key><array><string>$GROUP</string></array>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Add :PlannerAppGroup string $GROUP" "$APP/Contents/Info.plist"
codesign --force --options runtime --timestamp --entitlements .build/widget.entitlements --sign "$FORGETIT_SIGNING_IDENTITY" "$EXT"
codesign --force --options runtime --timestamp --entitlements .build/planner.entitlements --sign "$FORGETIT_SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
STAGE=$(mktemp -d /tmp/forget-it-widget-dmg.XXXXXX)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "forget it" -srcfolder "$STAGE" -ov -format UDZO "$PWD/dist/forget-it-widget.dmg"
echo "Signed widget build created. Notarize and staple before distribution; verify the widget on a clean Mac."
