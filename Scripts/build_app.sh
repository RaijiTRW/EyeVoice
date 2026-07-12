#!/bin/bash
# Builds EyeVoice.app into build/
set -euo pipefail
cd "$(dirname "$0")/.."

echo "── building binary ──"
swift build -c release

APP="build/EyeVoice.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp .build/release/EyeVoice "$APP/Contents/MacOS/EyeVoice"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/VoiceSamples/*.mp3 "$APP/Contents/Resources/" 2>/dev/null || true
ditto .build/release/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"

# App icon: use the designed artwork if present, else generate the ASCII eye
if [ ! -f build/AppIcon.icns ]; then
    echo "── building icon ──"
    mkdir -p build/AppIcon.iconset
    if [ -f Resources/AppIcon-source.png ]; then
        cp Resources/AppIcon-source.png build/icon_1024.png
    else
        swift Scripts/make_icon.swift build/icon_1024.png
    fi
    for s in 16 32 64 128 256 512; do
        sips -z $s $s build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
        d=$((s * 2))
        sips -z $d $d build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

SIGN_IDENTITY="${EYEVOICE_CODESIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
        | head -n 1)"
fi

if [ -n "$SIGN_IDENTITY" ]; then
    echo "── signing with persistent identity: $SIGN_IDENTITY ──"
    # A stable Apple signing identity gives EyeVoice a stable designated
    # requirement. macOS TCC can then retain Microphone and Audio Capture
    # permissions between local rebuilds instead of treating every build as a
    # different ad-hoc application.
    TIMESTAMP_ARGS=(--timestamp=none)
    if [[ "$SIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
        TIMESTAMP_ARGS=(--timestamp)
    fi
    codesign --force --deep --options runtime "${TIMESTAMP_ARGS[@]}" \
        --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
    codesign --force --options runtime "${TIMESTAMP_ARGS[@]}" \
        --sign "$SIGN_IDENTITY" "$APP"
else
    echo "error: no Apple code-signing identity found" >&2
    echo "Set EYEVOICE_CODESIGN_IDENTITY to a persistent identity." >&2
    exit 1
fi

echo "done: $APP"
