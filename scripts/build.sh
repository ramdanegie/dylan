#!/usr/bin/env bash
# Builds build/Dylan.app with SwiftPM + Command Line Tools only (no Xcode). PRD T0.1.
#   ./scripts/build.sh [--test] [--run] [--debug]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release; TEST=0; RUN=0
for a in "$@"; do
  case "$a" in
    --test) TEST=1 ;;
    --run) RUN=1 ;;
    --debug) CONFIG=debug ;;
    *) echo "unknown option: $a" >&2; exit 64 ;;
  esac
done

if [[ $TEST == 1 ]]; then
  # Separate scratch path: with CLT, `swift test` loses the Testing macro plugin when it reuses a `swift build` cache.
  swift test --scratch-path .build-test
fi

swift build -c "$CONFIG" --product Dylan
swift build -c "$CONFIG" --product dylan-cli
swift build -c "$CONFIG" --product dylan-fan-helper
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

APP=build/Dylan.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons"
cp "$BIN/Dylan" "$APP/Contents/MacOS/Dylan"
# Root fan helper (FR-99), registered with SMAppService.daemon from this plist.
cp "$BIN/dylan-fan-helper" "$APP/Contents/MacOS/dylan-fan-helper"
cp Resources/io.github.ramdanegie.dylan.fan.plist "$APP/Contents/Library/LaunchDaemons/"
# Helpers/, not MacOS/: "Dylan" and "dylan" collide on a case-insensitive disk.
cp "$BIN/dylan-cli" "$APP/Contents/Helpers/dylan"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Sources/Dylan/Resources/*.lproj "$APP/Contents/Resources/"
cp CHANGELOG.md CHANGELOG.id.md "$APP/Contents/Resources/"   # What's New after an update

# The app icon (design 4c) lives in the repo. The design folder is synced from the design tool and may hold
# other exports, so it is never read here; copy a new icon into Resources/AppIcon.iconset on purpose.
ICONSET="Resources/AppIcon.iconset"
if [[ ! -f Resources/Dylan.icns ]] || [[ -n "$(find "$ICONSET" -newer Resources/Dylan.icns -print -quit)" ]]; then
  iconutil -c icns "$ICONSET" -o Resources/Dylan.icns
fi
[[ -f Resources/Dylan.icns ]] && cp Resources/Dylan.icns "$APP/Contents/Resources/Dylan.icns"

# Ad-hoc signature + hardened runtime by default. TCC permissions are tied to this signature (see README).
# DYLAN_SIGN_IDENTITY="Apple Development: …" signs with a team certificate instead: permissions then survive
# rebuilds, and the fan helper accepts the app (it only trusts its own team, so ad-hoc builds just monitor).
SIGN="${DYLAN_SIGN_IDENTITY:--}"
codesign --force --options runtime --timestamp=none --sign "$SIGN" "$APP/Contents/Helpers/dylan"
codesign --force --options runtime --timestamp=none --identifier io.github.ramdanegie.dylan.fan --sign "$SIGN" "$APP/Contents/MacOS/dylan-fan-helper"
codesign --force --options runtime --timestamp=none --entitlements Resources/Dylan.entitlements --sign "$SIGN" "$APP"
codesign --verify --strict "$APP"
echo "✓ $APP"

if [[ $RUN == 1 ]]; then
  pkill -x Dylan 2>/dev/null || true
  sleep 0.3
  open "$APP"
fi
