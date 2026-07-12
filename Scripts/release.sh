#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST="Resources/Info.plist"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")}"
BUILD_NUMBER="${2:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")}"
RELEASE_DIR="build/releases"
APP="build/EyeVoice.app"
DMG="$RELEASE_DIR/EyeVoice-$VERSION.dmg"
DOWNLOAD_BASE="https://seexmgivktuycodxrjhs.supabase.co/storage/v1/object/public/eyevoice-releases/"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: version must use MAJOR.MINOR.PATCH (for example 1.2.0)" >&2
    exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "error: build number must be an integer" >&2
    exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"

if [ -z "${EYEVOICE_CODESIGN_IDENTITY:-}" ]; then
    EYEVOICE_CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
        | head -n 1)"
    if [ -z "$EYEVOICE_CODESIGN_IDENTITY" ]; then
        EYEVOICE_CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
            | head -n 1)"
    fi
fi
export EYEVOICE_CODESIGN_IDENTITY

if [ -z "$EYEVOICE_CODESIGN_IDENTITY" ]; then
    echo "error: no code-signing identity found" >&2
    exit 1
fi

echo "── EyeVoice $VERSION ($BUILD_NUMBER) ──"
Scripts/build_app.sh
codesign --verify --deep --strict --verbose=2 "$APP"

IS_PRODUCTION=false
if [[ "$EYEVOICE_CODESIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
    IS_PRODUCTION=true
    if [ -z "${EYEVOICE_NOTARY_PROFILE:-}" ]; then
        echo "error: set EYEVOICE_NOTARY_PROFILE to a notarytool Keychain profile" >&2
        exit 1
    fi

    echo "── notarizing app ──"
    ditto -c -k --keepParent "$APP" build/EyeVoice-notary.zip
    xcrun notarytool submit build/EyeVoice-notary.zip \
        --keychain-profile "$EYEVOICE_NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
else
    echo "warning: Developer ID Application is unavailable."
    echo "The DMG will be suitable for local testing, not public distribution."
fi

echo "── creating DMG ──"
mkdir -p "$RELEASE_DIR"
Scripts/create_dmg.sh "$VERSION" "$DMG"

if [ "$IS_PRODUCTION" = true ]; then
    codesign --force --timestamp --sign "$EYEVOICE_CODESIGN_IDENTITY" "$DMG"
    echo "── notarizing DMG ──"
    xcrun notarytool submit "$DMG" \
        --keychain-profile "$EYEVOICE_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

NOTES_SOURCE="Resources/ReleaseNotes/$VERSION.md"
NOTES_TARGET="$RELEASE_DIR/EyeVoice-$VERSION.md"
if [ -f "$NOTES_SOURCE" ]; then
    cp "$NOTES_SOURCE" "$NOTES_TARGET"
elif [ ! -f "$NOTES_TARGET" ]; then
    printf '# EyeVoice %s\n\nОбновление EyeVoice.\n' "$VERSION" > "$NOTES_TARGET"
fi

echo "── signing update and generating appcast ──"
rm -f "$RELEASE_DIR/EyeVoice-latest.dmg"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "$DOWNLOAD_BASE" \
    --release-notes-url-prefix "$DOWNLOAD_BASE" \
    --maximum-versions 5 \
    "$RELEASE_DIR"

cp "$DMG" "$RELEASE_DIR/EyeVoice-latest.dmg"

echo "done: $DMG"
echo "feed: $RELEASE_DIR/appcast.xml"
