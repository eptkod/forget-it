#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
swiftc -swift-version 5 -module-cache-path "$PWD/.build/module-cache" Sources/ForgetIt/BrandArtwork.swift scripts/make-icon.swift -o .build/make-icon
.build/make-icon packaging/AppIcon.iconset
iconutil -c icns packaging/AppIcon.iconset -o packaging/AppIcon.icns
cp packaging/AppIcon.icns assets/brand/forget-it.icns
mkdir -p dist
/usr/bin/ditto -c -k --sequesterRsrc --keepParent assets/brand dist/forget-it-logo.zip
