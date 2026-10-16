#!/bin/bash
set -euo pipefail
# Arguments are paths to an already signed app, output image, and release documents.
APP="$1"
OUTPUT="$2"
DOCUMENTS="$3"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/mac-monitor-dmg.XXXXXX")"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac-monitor-image.XXXXXX")"
MOUNTED=0
cleanup() {
  if [[ "$MOUNTED" == 1 ]]; then hdiutil detach "$WORK/mount" >/dev/null || true; fi
  rm -rf "$STAGE" "$WORK"
}
trap cleanup EXIT
ditto --norsrc --noextattr "$APP" "$STAGE/Mac Monitor.app"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/Documentation"
cp "$DOCUMENTS/INSTALL.md" "$DOCUMENTS/LICENSE" "$DOCUMENTS/SECURITY.md" "$DOCUMENTS/THIRD_PARTY_NOTICES.md" "$DOCUMENTS/m1ddc-LICENSE.txt" "$STAGE/Documentation/"
cp "$APP/Contents/Resources/MacMonitorIcon.icns" "$STAGE/.VolumeIcon.icns"
# Set the flag on the mounted volume itself: srcfolder does not preserve root FinderInfo.
SETFILE="$(xcrun --find SetFile)"
hdiutil create -volname 'Mac Monitor' -srcfolder "$STAGE" -format UDRW "$WORK/writable.dmg"
mkdir "$WORK/mount"
hdiutil attach -nobrowse -mountpoint "$WORK/mount" "$WORK/writable.dmg" >/dev/null
MOUNTED=1
"$SETFILE" -a C "$WORK/mount"
hdiutil detach "$WORK/mount" >/dev/null
MOUNTED=0
hdiutil convert "$WORK/writable.dmg" -ov -format UDZO -imagekey zlib-level=9 -o "$OUTPUT"
