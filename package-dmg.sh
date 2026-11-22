#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ $# -ne 1 || ! "$1" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?$ ]]; then
    echo "Usage: $0 vMAJOR.MINOR[.PATCH] (for example, v1.0 or v1.2.3)" >&2
    exit 1
fi

export GLANCE_VERSION="${1#v}"
./build.sh --arch arm64 --arch x86_64

GLANCE_APP="$PWD/dist/Glance.app"
for binary in Glance GlancePowerHelper; do
    for arch in arm64 x86_64; do
        lipo "$GLANCE_APP/Contents/MacOS/$binary" -verify_arch "$arch"
    done
done
codesign --verify --deep --strict "$GLANCE_APP"

GLANCE_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/glance-dmg.XXXXXX")"
trap 'rm -rf "$GLANCE_STAGE"' EXIT
ditto "$GLANCE_APP" "$GLANCE_STAGE/Glance.app"
ln -s /Applications "$GLANCE_STAGE/Applications"

GLANCE_DMG="Glance-$GLANCE_VERSION-universal.dmg"
hdiutil create -volname "Glance $GLANCE_VERSION" -srcfolder "$GLANCE_STAGE" \
    -format UDZO -ov "$PWD/dist/$GLANCE_DMG"
hdiutil verify "$PWD/dist/$GLANCE_DMG"

# With a notarytool keychain profile, sign the DMG, notarize it, and staple the tickets to the DMG and app.
if [[ -n "${GLANCE_NOTARY_PROFILE:-}" ]]; then
    GLANCE_SIGN_IDENTITY="$(codesign -dvv "$GLANCE_APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p')"
    if [[ -z "$GLANCE_SIGN_IDENTITY" ]]; then
        echo "Notarization needs a Developer ID Application signature on $GLANCE_APP" >&2
        exit 1
    fi
    codesign --force --timestamp --sign "$GLANCE_SIGN_IDENTITY" "$PWD/dist/$GLANCE_DMG"
    xcrun notarytool submit "$PWD/dist/$GLANCE_DMG" --keychain-profile "$GLANCE_NOTARY_PROFILE" --wait
    xcrun stapler staple "$PWD/dist/$GLANCE_DMG"
    xcrun stapler staple "$GLANCE_APP"
    spctl --assess --type open --context context:primary-signature --verbose "$PWD/dist/$GLANCE_DMG"
    spctl --assess --type execute --verbose "$GLANCE_APP"
fi

cd dist
shasum -a 256 "$GLANCE_DMG" > "$GLANCE_DMG.sha256"
echo "Packaged $PWD/$GLANCE_DMG"
