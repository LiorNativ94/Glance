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
    lipo "$GLANCE_APP/Contents/MacOS/$binary" -verify_arch arm64 x86_64
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

cd dist
shasum -a 256 "$GLANCE_DMG" > "$GLANCE_DMG.sha256"
echo "Packaged $PWD/$GLANCE_DMG"
