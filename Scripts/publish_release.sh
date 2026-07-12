#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST="Resources/Info.plist"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")}"
RELEASE_DIR="build/releases"
DMG="$RELEASE_DIR/EyeVoice-$VERSION.dmg"
NOTES="$RELEASE_DIR/EyeVoice-$VERSION.md"
APPCAST="$RELEASE_DIR/appcast.xml"
LATEST="$RELEASE_DIR/EyeVoice-latest.dmg"
APP="build/EyeVoice.app"

if ! codesign -dv --verbose=4 "$APP" 2>&1 | grep -q '^Authority=Developer ID Application:'; then
    if [ "${EYEVOICE_ALLOW_TEST_PUBLISH:-0}" != "1" ]; then
        echo "error: EyeVoice is not signed with Developer ID Application." >&2
        echo "Public users will be blocked by Gatekeeper." >&2
        echo "For an internal-only upload, set EYEVOICE_ALLOW_TEST_PUBLISH=1." >&2
        exit 1
    fi
    echo "warning: publishing an internal test build signed with Apple Development"
fi

for file in "$DMG" "$APPCAST"; do
    if [ ! -f "$file" ]; then
        echo "error: missing $file; run Scripts/release.sh first" >&2
        exit 1
    fi
done

echo "── publishing EyeVoice $VERSION ──"
supabase --yes --experimental storage rm \
    "ss:///eyevoice-releases/$(basename "$DMG")" >/dev/null 2>&1 || true
supabase --experimental storage cp "$DMG" \
    "ss:///eyevoice-releases/$(basename "$DMG")" \
    --content-type "application/x-apple-diskimage" \
    --cache-control "public,max-age=31536000,immutable"

# The website always points to this short-lived alias. Sparkle keeps using the
# immutable versioned DMG from appcast.xml.
cp "$DMG" "$LATEST"
supabase --yes --experimental storage rm \
    "ss:///eyevoice-releases/EyeVoice-latest.dmg" >/dev/null 2>&1 || true
supabase --experimental storage cp "$LATEST" \
    "ss:///eyevoice-releases/EyeVoice-latest.dmg" \
    --content-type "application/x-apple-diskimage" \
    --cache-control "no-cache,max-age=0,must-revalidate"

if [ -f "$NOTES" ]; then
    supabase --yes --experimental storage rm \
        "ss:///eyevoice-releases/$(basename "$NOTES")" >/dev/null 2>&1 || true
    supabase --experimental storage cp "$NOTES" \
        "ss:///eyevoice-releases/$(basename "$NOTES")" \
        --content-type "text/markdown" \
        --cache-control "public,max-age=3600"
fi

supabase --yes --experimental storage rm \
    "ss:///eyevoice-releases/appcast.xml" >/dev/null 2>&1 || true
supabase --experimental storage cp "$APPCAST" \
    "ss:///eyevoice-releases/appcast.xml" \
    --content-type "application/xml" \
    --cache-control "public,max-age=300"

echo "published: EyeVoice $VERSION"
