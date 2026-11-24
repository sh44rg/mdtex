#!/bin/bash
# Build a shareable Apple silicon disk image. See DISTRIBUTION.md for signing.
set -euo pipefail
cd "$(dirname "$0")"

if [[ -n "${MDTEX_NOTARY_PROFILE:-}" && -z "${MDTEX_SIGNING_IDENTITY:-}" ]]; then
  echo "Notarization requires MDTEX_SIGNING_IDENTITY." >&2
  exit 1
fi

./build-app.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' app/Info.plist)
mkdir -p release build.noindex
staging=$(mktemp -d "$PWD/build.noindex/release.XXXXXX")
trap 'rm -rf "$staging"' EXIT
image="$PWD/release/mdtex-${version}-apple-silicon.dmg"

ditto build.noindex/mdtex.app "$staging/mdtex.app"
ln -s /Applications "$staging/Applications"
cp INSTALL.txt "$staging/Read Me.txt"
rm -f "$image"
hdiutil create -quiet -volname "mdtex" -srcfolder "$staging" -format UDZO "$image"

if [[ -n "${MDTEX_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$MDTEX_SIGNING_IDENTITY" "$image"
fi
if [[ -n "${MDTEX_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$image" --keychain-profile "$MDTEX_NOTARY_PROFILE" --wait
  xcrun stapler staple "$image"
  xcrun stapler validate "$image"
fi

echo "Created $image"
