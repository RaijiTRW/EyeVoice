#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: Scripts/create_dmg.sh VERSION [OUTPUT_DMG]}"
APP="build/EyeVoice.app"
OUTPUT="${2:-build/releases/EyeVoice-$VERSION.dmg}"
VOL_NAME="EyeVoice Installer"
STAGE_DIR="build/dmg-root"
ASSET_DIR="build/dmg-assets"
RW_IMAGE="build/EyeVoice-$VERSION-rw.dmg"
MOUNT_DIR=""
DEVICE=""

cleanup() {
    if [ -n "$DEVICE" ]; then hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || true; fi
    rm -f "$RW_IMAGE"
}
trap cleanup EXIT

if [ ! -d "$APP" ]; then
    echo "error: missing $APP; run Scripts/build_app.sh first" >&2
    exit 1
fi

rm -rf "$STAGE_DIR" "$ASSET_DIR" "$OUTPUT" "$RW_IMAGE"
mkdir -p "$STAGE_DIR/.background" "$ASSET_DIR" "$(dirname "$OUTPUT")"

swift Scripts/make_dmg_background.swift "$ASSET_DIR/background.png" "$VERSION"
ditto "$APP" "$STAGE_DIR/EyeVoice.app"
ln -s /Applications "$STAGE_DIR/Applications"
cp "$ASSET_DIR/background.png" "$STAGE_DIR/.background/background.png"

hdiutil create -quiet -volname "$VOL_NAME" -srcfolder "$STAGE_DIR" \
    -fs HFS+ -format UDRW -size 48m "$RW_IMAGE"

ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen -nobrowse "$RW_IMAGE")"
DEVICE="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/Apple_HFS/ {print $1; exit}')"
MOUNT_DIR="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/Apple_HFS/ {sub(/^.*\/Volumes\//, "/Volumes/"); print; exit}')"

if [ -z "$DEVICE" ] || [ -z "$MOUNT_DIR" ]; then
    echo "error: unable to mount DMG as a Finder volume" >&2
    exit 1
fi

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set bounds of container window to {120, 120, 840, 580}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 104
        set text size of theViewOptions to 13
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "EyeVoice.app" of container window to {190, 247}
        set position of item "Applications" of container window to {530, 247}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

SetFile -a V "$MOUNT_DIR/.background"
SetFile -a V "$MOUNT_DIR/.DS_Store" 2>/dev/null || true
sync
hdiutil detach "$DEVICE" -quiet
DEVICE=""

hdiutil convert -quiet "$RW_IMAGE" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT"
echo "done: $OUTPUT"
