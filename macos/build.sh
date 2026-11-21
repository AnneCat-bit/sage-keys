#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="macos/build/Sage Keys.app"
resources="$app/Contents/Resources"
pet="$resources/Pet"
mkdir -p "$app/Contents/MacOS" "$pet/assets/fonts" "$resources/Licenses" macos/build/evidence
cp macos/Info.plist "$app/Contents/"
cp macos/Web/index.html macos/Web/pet.css style.css "$pet/"
cp assets/fonts/*.woff2 "$pet/assets/fonts/"
cp assets/fonts/*LICENSE.txt assets/THREE-LICENSE.txt docs/AUDIO.md "$resources/Licenses/"
node macos/Web/bundle.mjs "$pet/pet.js"
iconset=macos/build/Sage.iconset
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" macos/Sage.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  twice=$((size * 2))
  sips -z "$twice" "$twice" macos/Sage.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$resources/Sage.icns"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos13.0 macos/Sources/*.swift -o "$app/Contents/MacOS/SageKeys"
codesign --force --sign - --options runtime --timestamp=none "$app"
file "$app/Contents/MacOS/SageKeys"
(cd "$resources" && find Pet Licenses -type f -exec shasum -a 256 {} \;) > macos/build/evidence/bundled-sha256.txt
