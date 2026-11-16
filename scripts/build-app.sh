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

# Signed with the same certificate every build when one is set up (SIGNING_IDENTITY, from
# CI's secrets), so macOS keeps TenFoot's Accessibility permission across updates.
# Otherwise an ad-hoc signature, which macOS treats as a new app every build.
if [ -n "${SIGNING_IDENTITY:-}" ]; then
  codesign --force --sign "$SIGNING_IDENTITY" ${SIGNING_KEYCHAIN:+--keychain "$SIGNING_KEYCHAIN"} "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --display --requirements - "$APP"

(cd build && ditto -c -k --keepParent TenFoot.app TenFoot.zip)
echo "Built $APP and build/TenFoot.zip"
