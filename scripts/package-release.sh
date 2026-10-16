#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="$(cat VERSION)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$ ]]; then
  echo "Invalid release version." >&2
  exit 1
fi
RELEASE_DIR="${MAC_MONITOR_RELEASE_DIR:-$ROOT/dist}"
case "$RELEASE_DIR" in /*) ;; *) RELEASE_DIR="$ROOT/$RELEASE_DIR" ;; esac
SIGNING_IDENTITY="${MAC_MONITOR_RELEASE_SIGNING_IDENTITY:--}"
case "$SIGNING_IDENTITY" in
  -|"Developer ID Application:"*) ;;
  *) echo "Release signing must be ad-hoc (-) or Developer ID Application." >&2; exit 1 ;;
esac
mkdir -p "$RELEASE_DIR"
export MAC_MONITOR_BUILD_DIR="$RELEASE_DIR/build"
export MAC_MONITOR_SIGNING_IDENTITY="$SIGNING_IDENTITY"
./scripts/build.sh
./scripts/test.sh
STAGE="$(mktemp -d "$RELEASE_DIR/.stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP_FOLDER="MacMonitor-$VERSION-arm64"
SOURCE_FOLDER="mac-monitor"
mkdir -p "$STAGE/$APP_FOLDER" "$STAGE/$SOURCE_FOLDER/tools"
ditto --norsrc --noextattr "$MAC_MONITOR_BUILD_DIR/Mac Monitor.app" "$STAGE/$APP_FOLDER/Mac Monitor.app"
cp docs/INSTALL.md LICENSE SECURITY.md THIRD_PARTY_NOTICES.md "$STAGE/$APP_FOLDER/"
cp Vendor/m1ddc/LICENSE "$STAGE/$APP_FOLDER/m1ddc-LICENSE.txt"
# Select public inputs explicitly; local diagnostics and credentials never belong here.
for item in .github Assets Sources Resources Tests Vendor scripts docs LICENSE README.md README.en.md CHANGELOG.md CONTRIBUTING.md SECURITY.md THIRD_PARTY_NOTICES.md VERSION .gitignore; do
  ditto --norsrc --noextattr "$ROOT/$item" "$STAGE/$SOURCE_FOLDER/$item"
done
cp tools/IconGenerator.swift "$STAGE/$SOURCE_FOLDER/tools/"
APP_ZIP="$APP_FOLDER.zip"
SOURCE_ZIP="mac-monitor-$VERSION-source.zip"
ditto -c -k --keepParent --norsrc --noextattr "$STAGE/$APP_FOLDER" "$RELEASE_DIR/$APP_ZIP"
ditto -c -k --keepParent --norsrc --noextattr "$STAGE/$SOURCE_FOLDER" "$RELEASE_DIR/$SOURCE_ZIP"
(cd "$RELEASE_DIR" && shasum -a 256 "$APP_ZIP" "$SOURCE_ZIP" > SHA256SUMS.txt)
echo "Release prepared: $RELEASE_DIR/$APP_ZIP"
echo "Source archive: $RELEASE_DIR/$SOURCE_ZIP"
