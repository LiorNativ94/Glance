#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release "$@"
GLANCE_BIN="$(swift build -c release "$@" --show-bin-path)"
GLANCE_APP="$PWD/dist/Glance.app"
mkdir -p "$GLANCE_APP/Contents/MacOS" "$GLANCE_APP/Contents/Resources"
cp "$GLANCE_BIN/Glance" "$GLANCE_APP/Contents/MacOS/Glance"
cp "$GLANCE_BIN/GlancePowerHelper" "$GLANCE_APP/Contents/MacOS/GlancePowerHelper"
cp Resources/Info.plist "$GLANCE_APP/Contents/Info.plist"
if [[ -n "${GLANCE_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $GLANCE_VERSION" "$GLANCE_APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $GLANCE_VERSION" "$GLANCE_APP/Contents/Info.plist"
fi
cp Resources/Lucide-LICENSE.txt "$GLANCE_APP/Contents/Resources/Lucide-LICENSE.txt"
cp -R "$GLANCE_BIN/Glance_Glance.bundle" "$GLANCE_APP/Contents/Resources/"
swift Resources/MakeIcon.swift "$GLANCE_APP/Contents/Resources/GlanceIcon.icns"
codesign --force --sign - "$GLANCE_APP/Contents/MacOS/GlancePowerHelper"
codesign --force --sign - "$GLANCE_APP"
echo "Built $GLANCE_APP"
