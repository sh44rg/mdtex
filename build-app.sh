#!/bin/bash
# Builds build.noindex/mdtex.app (the .noindex name keeps this copy out of Spotlight). With --install, also copies it to /Applications
# and registers it with Finder as a Markdown viewer.
set -euo pipefail
cd "$(dirname "$0")"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
APP=build.noindex/mdtex.app
ICONSET=build.noindex/AppIcon.iconset

npm run build --silent

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"

# Match the minimum macOS version in Info.plist and target Apple silicon.
swiftc -O -target arm64-apple-macos13.0 app/main.swift app/FindBar.swift \
  -o "$APP/Contents/MacOS/mdtex" -framework Cocoa -framework WebKit
cp app/Info.plist "$APP/Contents/Info.plist"
cp -R dist "$APP/Contents/Resources/web"
cp src/fonts/INTER-LICENSE.txt "$APP/Contents/Resources/Inter-LICENSE.txt"

# Icon
swift app/make-icon.swift node_modules/latex.css/fonts/LM-regular.ttf build.noindex/icon.png
for s in 16 32 128 256 512; do
  sips -z $s $s build.noindex/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) build.noindex/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "${MDTEX_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$MDTEX_SIGNING_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/mdtex.app
  cp -R "$APP" /Applications/mdtex.app
  "$LSREGISTER" -u "$PWD/$APP" >/dev/null 2>&1 || true
  "$LSREGISTER" -f /Applications/mdtex.app
  echo "Installed /Applications/mdtex.app"
fi
