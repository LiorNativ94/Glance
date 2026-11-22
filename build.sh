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
# Prefer a valid Developer ID Application certificate, then Apple Development; fall back to ad hoc signing.
if [[ -z "${GLANCE_SIGN_IDENTITY:-}" ]]; then
    GLANCE_SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk '
        /CSSMERR_/ { next }
        /"Developer ID Application: / && !devid { devid = $2 }
        /"Apple Development: / && !dev { dev = $2 }
        END { print devid ? devid : dev }')"
fi
GLANCE_SIGN_IDENTITY="${GLANCE_SIGN_IDENTITY:--}"
# Notarization requires the hardened runtime and a secure timestamp; ad hoc signatures get neither.
GLANCE_SIGN_OPTIONS=()
[[ "$GLANCE_SIGN_IDENTITY" != "-" ]] && GLANCE_SIGN_OPTIONS=(--options runtime --timestamp)
codesign --force ${GLANCE_SIGN_OPTIONS[@]+"${GLANCE_SIGN_OPTIONS[@]}"} --sign "$GLANCE_SIGN_IDENTITY" "$GLANCE_APP/Contents/MacOS/GlancePowerHelper"
codesign --force ${GLANCE_SIGN_OPTIONS[@]+"${GLANCE_SIGN_OPTIONS[@]}"} --sign "$GLANCE_SIGN_IDENTITY" "$GLANCE_APP"
echo "Built $GLANCE_APP"
