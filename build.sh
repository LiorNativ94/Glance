#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
GLANCE_BIN="$(swift build -c release --show-bin-path)"
GLANCE_APP="$PWD/dist/Glance.app"
mkdir -p "$GLANCE_APP/Contents/MacOS" "$GLANCE_APP/Contents/Resources"
cp "$GLANCE_BIN/Glance" "$GLANCE_APP/Contents/MacOS/Glance"
cp "$GLANCE_BIN/GlancePowerHelper" "$GLANCE_APP/Contents/MacOS/GlancePowerHelper"
cp Resources/Info.plist "$GLANCE_APP/Contents/Info.plist"
cp Resources/Lucide-LICENSE.txt "$GLANCE_APP/Contents/Resources/Lucide-LICENSE.txt"
swift Resources/MakeIcon.swift "$GLANCE_APP/Contents/Resources/GlanceIcon.icns"
codesign --force --sign - "$GLANCE_APP/Contents/MacOS/GlancePowerHelper"
codesign --force --sign - "$GLANCE_APP"
echo "Built $GLANCE_APP"
