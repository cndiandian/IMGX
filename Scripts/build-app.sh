#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app="dist/IMGX.app"
mkdir -p "$app/Contents/MacOS"
cp "$binary_dir/IMGX" "$app/Contents/MacOS/IMGX"
cp Scripts/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
echo "应用已生成：$PWD/$app"
