#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD_DIR="${MAC_MONITOR_BUILD_DIR:-$ROOT/build}"
case "$BUILD_DIR" in /*) ;; *) BUILD_DIR="$ROOT/$BUILD_DIR" ;; esac
APP="$BUILD_DIR/Mac Monitor.app"
if [ "$(uname -m)" != "arm64" ]; then
  echo "This build supports Apple Silicon Macs only." >&2
  exit 1
fi
if [ -f "$APP/Contents/MacOS/MacMonitor" ] && /usr/sbin/lsof -t "$APP/Contents/MacOS/MacMonitor" >/dev/null 2>&1; then
  echo "This app is running. Quit it first, or set MAC_MONITOR_BUILD_DIR to another directory." >&2
  exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons" "$BUILD_DIR/cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/cache"

# Accessibility permission is linked to the code-signing identity. Prefer a
# stable local Apple Development identity so a rebuild is still the same app
# to macOS. A developer can override it for another machine; ad-hoc signing is
# kept only as a no-identity fallback.
SIGNING_IDENTITY="${MAC_MONITOR_SIGNING_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -n 1)"
fi
if [ -z "$SIGNING_IDENTITY" ]; then
  SIGNING_IDENTITY="-"
  echo "Warning: no Apple Development identity found; using ad-hoc signing. Accessibility may need re-approval after rebuilding."
else
  echo "Signing with: $SIGNING_IDENTITY"
fi
xcrun clang -fobjc-arc -fmodules -target arm64-apple-macos14.0 -c Sources/Native/MonitorBridge.m -o "$BUILD_DIR/MonitorBridge.o"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos14.0 -module-cache-path "$BUILD_DIR/cache" \
  -import-objc-header Sources/Native/MonitorBridge.h Sources/Shared/*.swift Sources/MacMonitor/*.swift "$BUILD_DIR/MonitorBridge.o" \
  -framework AppKit -framework SwiftUI -framework CoreGraphics -framework IOKit -framework Security -framework ServiceManagement \
  -o "$APP/Contents/MacOS/MacMonitor"
xcrun clang -fmodules -target arm64-apple-macos14.0 -DMAX_DISPLAYS=32 -I Vendor/m1ddc/headers \
  Vendor/m1ddc/sources/*.m -framework CoreDisplay -o "$APP/Contents/MacOS/m1ddc"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos14.0 -module-cache-path "$BUILD_DIR/cache" \
  Sources/Shared/*.swift Sources/MacMonitor/HiDPISize.swift Sources/Native/OverrideHelper.swift Sources/Native/OverrideService.swift -framework Security -o "$APP/Contents/MacOS/DisplayOverrideHelper"
xcrun clang -fobjc-arc -fmodules -fmodules-cache-path="$BUILD_DIR/cache" -target arm64-apple-macos14.0 \
  Sources/Native/SidecarTool.m -framework Foundation -o "$APP/Contents/MacOS/SidecarTool"
cp Resources/LaunchDaemons/*.plist "$APP/Contents/Library/LaunchDaemons/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/English.json "$APP/Contents/Resources/English.json"
cp Resources/Support.json "$APP/Contents/Resources/Support.json"
cp Assets/Support/MB-Bank-QR.png "$APP/Contents/Resources/SupportBankQR.png"
cp Vendor/m1ddc/LICENSE "$APP/Contents/Resources/m1ddc-LICENSE.txt"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"

ICON_PNG="$BUILD_DIR/MacMonitorIcon.png"
ICONSET="$BUILD_DIR/MacMonitorIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
xcrun swiftc -O -module-cache-path "$BUILD_DIR/cache" tools/IconGenerator.swift -framework AppKit -o "$BUILD_DIR/IconGenerator"
"$BUILD_DIR/IconGenerator" "$ICON_PNG"
for spec in \
  '16 icon_16x16.png' \
  '32 icon_16x16@2x.png' \
  '32 icon_32x32.png' \
  '64 icon_32x32@2x.png' \
  '128 icon_128x128.png' \
  '256 icon_128x128@2x.png' \
  '256 icon_256x256.png' \
  '512 icon_256x256@2x.png' \
  '512 icon_512x512.png' \
  '1024 icon_512x512@2x.png'; do
  set -- $spec
  sips -z "$1" "$1" "$ICON_PNG" --out "$ICONSET/$2" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/MacMonitorIcon.icns"
SIGNING_OPTIONS=(--force --sign "$SIGNING_IDENTITY")
case "$SIGNING_IDENTITY" in "Developer ID Application:"*) SIGNING_OPTIONS+=(--options runtime --timestamp) ;; esac
codesign "${SIGNING_OPTIONS[@]}" "$APP/Contents/MacOS/m1ddc"
codesign "${SIGNING_OPTIONS[@]}" --identifier local.anle.MacMonitor.SidecarTool "$APP/Contents/MacOS/SidecarTool"
codesign "${SIGNING_OPTIONS[@]}" --identifier local.anle.MacMonitor.DisplayOverrideHelper "$APP/Contents/MacOS/DisplayOverrideHelper"
codesign "${SIGNING_OPTIONS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
