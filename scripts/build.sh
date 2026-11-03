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
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

APP=build/Dylan.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/Dylan" "$APP/Contents/MacOS/Dylan"
# Helpers/, not MacOS/: "Dylan" and "dylan" collide on a case-insensitive disk.
cp "$BIN/dylan-cli" "$APP/Contents/Helpers/dylan"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Sources/Dylan/Resources/*.lproj "$APP/Contents/Resources/"

ICONSET="design/Dyland Notch Mockups/icon/Dylan.iconset"
if [[ ! -f Resources/Dylan.icns && -d "$ICONSET" ]]; then
  TMP="$(mktemp -d)/Dylan.iconset"; mkdir -p "$TMP"
  for f in "$ICONSET"/*.png; do n="$(basename "$f")"; cp "$f" "$TMP/${n/-2x/@2x}"; done
  iconutil -c icns "$TMP" -o Resources/Dylan.icns
fi
[[ -f Resources/Dylan.icns ]] && cp Resources/Dylan.icns "$APP/Contents/Resources/Dylan.icns"

# Ad-hoc signature + hardened runtime. TCC permissions are tied to this signature (see README).
codesign --force --options runtime --sign - "$APP/Contents/Helpers/dylan"
codesign --force --options runtime --entitlements Resources/Dylan.entitlements --sign - "$APP"
codesign --verify --strict "$APP"
echo "✓ $APP"

if [[ $RUN == 1 ]]; then
  pkill -x Dylan 2>/dev/null || true
  sleep 0.3
  open "$APP"
fi
