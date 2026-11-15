#!/usr/bin/env bash
# Builds TenFoot.app (Apple Silicon) into build/ and zips it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/TenFoot.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TenFoot" "$APP/Contents/MacOS/TenFoot"
cp scripts/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature so macOS will run it locally (not notarized).
codesign --force --sign - "$APP"

(cd build && ditto -c -k --keepParent TenFoot.app TenFoot.zip)
echo "Built $APP and build/TenFoot.zip"
