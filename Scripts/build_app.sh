#!/bin/bash
# Builds EyeVoice.app into build/
set -euo pipefail
cd "$(dirname "$0")/.."

echo "── building binary ──"
swift build -c release

APP="build/EyeVoice.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/EyeVoice "$APP/Contents/MacOS/EyeVoice"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/VoiceSamples/*.mp3 "$APP/Contents/Resources/" 2>/dev/null || true

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

echo "── signing (ad-hoc) ──"
codesign --force --deep --sign - "$APP"

echo "done: $APP"
