#!/bin/bash
# Build Snag.app: release build -> .app bundle -> icon -> ad-hoc codesign.
# Usage: scripts/build.sh [--install]   (--install copies to /Applications and relaunches)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Snag.app"
echo "[build] swift build -c release"
swift build -c release 2>&1 | grep -E "error|warning:|Compiling|Build complete" || true
BIN="$(swift build -c release --show-bin-path)/Snag"
[ -x "$BIN" ] || { echo "[build] FAILED: no binary"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Snag"
cp App/Info.plist "$APP/Contents/Info.plist"

if [ ! -f build/AppIcon.icns ] || [ App/MakeIcon.swift -nt build/AppIcon.icns ]; then
  echo "[build] icon"
  rm -rf build/AppIcon.iconset
  swift App/MakeIcon.swift build/AppIcon.iconset >/dev/null
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --identifier com.melvern.snag "$APP"
echo "[build] OK -> $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x Snag 2>/dev/null || true
  sleep 0.5
  rm -rf /Applications/Snag.app
  cp -R "$APP" /Applications/Snag.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Snag.app
  open /Applications/Snag.app
  echo "[build] installed + launched /Applications/Snag.app"
fi
