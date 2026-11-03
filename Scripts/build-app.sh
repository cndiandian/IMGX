#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app="dist/IMGX.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swift Scripts/generate-icon.swift dist/AppIcon.iconset
iconutil -c icns dist/AppIcon.iconset -o "$app/Contents/Resources/IMGX.icns"
cp Vendor/WebP/LICENSE "$app/Contents/Resources/WebP-LICENSE.txt"
cp "$binary_dir/IMGX" "$app/Contents/MacOS/IMGX"
cp Scripts/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
echo "应用已生成：$PWD/$app"
