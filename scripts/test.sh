#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="${MAC_MONITOR_BUILD_DIR:-$PWD/build}"
case "$BUILD_DIR" in /*) ;; *) BUILD_DIR="$PWD/$BUILD_DIR" ;; esac
mkdir -p "$BUILD_DIR/cache"
xcrun swiftc -swift-version 5 -module-cache-path "$BUILD_DIR/cache" Sources/MacMonitor/PopoverDismissal.swift Tests/PopoverDismissalTests.swift -o "$BUILD_DIR/PopoverDismissalTests"
"$BUILD_DIR/PopoverDismissalTests"
xcrun clang -std=c11 -Wall -Wextra -Werror Tests/ModeDescriptorTests.c -o "$BUILD_DIR/ModeDescriptorTests"
"$BUILD_DIR/ModeDescriptorTests"
xcrun clang -std=c11 -Wall -Wextra -Werror -I Vendor/m1ddc/headers Tests/DDCReplyTests.c -o "$BUILD_DIR/DDCReplyTests"
"$BUILD_DIR/DDCReplyTests"
xcrun clang -fmodules -fmodules-cache-path="$BUILD_DIR/cache" -I Vendor/m1ddc/headers \
  Tests/DDCTransportTests.m Vendor/m1ddc/sources/i2c.m -framework Foundation -o "$BUILD_DIR/DDCTransportTests"
"$BUILD_DIR/DDCTransportTests"
xcrun clang -std=c11 -Wall -Wextra -Werror -fsanitize=undefined -I Vendor/m1ddc/headers Tests/NumericInputTests.c -o "$BUILD_DIR/NumericInputTests"
"$BUILD_DIR/NumericInputTests"
xcrun clang -fmodules -fmodules-cache-path="$BUILD_DIR/cache" -fsanitize=address,undefined -I Vendor/m1ddc/headers \
  Tests/DDCSelectionTests.m Vendor/m1ddc/sources/ioregistry.m -framework Foundation -framework IOKit -framework ApplicationServices -framework CoreDisplay -o "$BUILD_DIR/DDCSelectionTests"
"$BUILD_DIR/DDCSelectionTests"
xcrun swiftc -swift-version 5 -module-cache-path "$BUILD_DIR/cache" Sources/Shared/*.swift Sources/MacMonitor/OverrideServiceClient.swift Tests/OverrideServiceSecurityTests.swift \
  -framework Security -framework ServiceManagement -o "$BUILD_DIR/OverrideServiceSecurityTests"
"$BUILD_DIR/OverrideServiceSecurityTests"
# Incomplete commands must be rejected before any hardware access.
for args in '-v display' 'display' '--verbose set'; do
  if "$BUILD_DIR/Mac Monitor.app/Contents/MacOS/m1ddc" $args >/dev/null; then
    echo "Incomplete DDC command unexpectedly accepted: $args" >&2; exit 1
  fi
done
# The root helper no longer accepts legacy command-line install/remove requests.
if "$BUILD_DIR/Mac Monitor.app/Contents/MacOS/DisplayOverrideHelper" enable 1 1 1920x1080 >/dev/null; then
  echo "Legacy privileged CLI unexpectedly accepted" >&2; exit 1
fi
xcrun swiftc -swift-version 5 -module-cache-path "$BUILD_DIR/cache" \
  -import-objc-header Sources/Native/MonitorBridge.h \
  Sources/MacMonitor/HiDPISize.swift Sources/MacMonitor/DisplayTypes.swift Sources/MacMonitor/BrightnessKeyInput.swift Sources/MacMonitor/BrightnessReading.swift Tests/PolicyTests.swift "$BUILD_DIR/MonitorBridge.o" \
  -framework AppKit -framework CoreGraphics -framework Security -o "$BUILD_DIR/PolicyTests"
"$BUILD_DIR/PolicyTests"
xcrun swiftc -swift-version 5 -module-cache-path "$BUILD_DIR/cache" \
  -import-objc-header Sources/Native/MonitorBridge.h \
  Sources/MacMonitor/HiDPISize.swift Sources/MacMonitor/DisplayTypes.swift Sources/MacMonitor/BrightnessReading.swift Sources/MacMonitor/Brightness.swift Tests/BrightnessPersistenceTests.swift "$BUILD_DIR/MonitorBridge.o" \
  -framework AppKit -framework CoreGraphics -framework Security -o "$BUILD_DIR/BrightnessPersistenceTests"
"$BUILD_DIR/BrightnessPersistenceTests"
xcrun swiftc -swift-version 5 -module-cache-path "$BUILD_DIR/cache" \
  -import-objc-header Sources/Native/MonitorBridge.h \
  Sources/MacMonitor/HiDPISize.swift Sources/MacMonitor/HiDPIScaling.swift Sources/MacMonitor/DisplayTypes.swift Tests/HiDPIScalingTests.swift "$BUILD_DIR/MonitorBridge.o" \
  -framework AppKit -framework CoreGraphics -framework Security -o "$BUILD_DIR/HiDPIScalingTests"
"$BUILD_DIR/HiDPIScalingTests"
xcrun swiftc -swift-version 5 -D OVERRIDE_TESTS -module-cache-path "$BUILD_DIR/cache" \
  Sources/MacMonitor/HiDPISize.swift Sources/Native/OverrideHelper.swift Tests/OverrideHelperTests.swift -o "$BUILD_DIR/OverrideHelperTests"
"$BUILD_DIR/OverrideHelperTests"
xcrun swiftc -swift-version 5 -module-cache-path "$BUILD_DIR/cache" \
  Sources/MacMonitor/Localization.swift Tests/LocalizationTests.swift -o "$BUILD_DIR/LocalizationTests"
"$BUILD_DIR/LocalizationTests"
xcrun swiftc -swift-version 5 -module-cache-path "$BUILD_DIR/cache" \
  -import-objc-header Sources/Native/MonitorBridge.h \
  Sources/MacMonitor/HiDPISize.swift Sources/MacMonitor/DisplayTypes.swift Sources/MacMonitor/DesktopPolicy.swift Tests/DesktopPolicyTests.swift "$BUILD_DIR/MonitorBridge.o" \
  -framework AppKit -framework CoreGraphics -framework Security -o "$BUILD_DIR/DesktopPolicyTests"
"$BUILD_DIR/DesktopPolicyTests"
codesign --verify --deep --strict "$BUILD_DIR/Mac Monitor.app"
plutil -lint "$BUILD_DIR/Mac Monitor.app/Contents/Info.plist"
