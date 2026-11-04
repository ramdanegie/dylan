#!/usr/bin/env bash
# Packs Dylan.app into build/Dylan-<version>.dmg for testers (drag to Applications).
#   DYLAN_SIGN_IDENTITY="Apple Development: …" ./scripts/dmg.sh
# Without a Developer ID + notarization, Gatekeeper blocks the first launch on another Mac;
# Resources/Install.txt (copied into the DMG) explains "Open Anyway".
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
STAGE="$(mktemp -d)/Dylan"
mkdir -p "$STAGE"
cp -R build/Dylan.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp Resources/Install.txt "$STAGE/Baca dulu - Read me.txt"

DMG="build/Dylan-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -quiet -volname "Dylan $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
if [[ -n "${DYLAN_SIGN_IDENTITY:-}" ]]; then codesign --sign "$DYLAN_SIGN_IDENTITY" --timestamp=none "$DMG"; fi
rm -rf "$(dirname "$STAGE")"
echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
