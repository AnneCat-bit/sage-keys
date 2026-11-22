#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
stage="$PWD/macos/build/dmg-stage"
mount="$PWD/macos/build/dmg-mount"
rw="$PWD/macos/build/install-rw.dmg"
dmg="$PWD/macos/build/Sage-Keys-Apple-Silicon.dmg"
mkdir -p "$stage/.background" "$mount"
ditto 'macos/build/Sage Keys.app' "$stage/Sage Keys.app"
ln -s /Applications "$stage/Applications"
xcrun swiftc macos/Sources/GuideDrawing.swift macos/Packaging/main.swift -o macos/build/dmg-art
macos/build/dmg-art "$stage/.background/install.png"
hdiutil create -ov -size 32m -fs HFS+ -volname 'Sage Keys' -srcfolder "$stage" -format UDRW "$rw"
hdiutil attach "$rw" -mountpoint "$mount" -nobrowse
trap 'hdiutil detach "$mount" >/dev/null 2>&1 || true' EXIT
osascript macos/Packaging/layout.applescript "$mount"
sync
hdiutil detach "$mount"
trap - EXIT
hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -o "$dmg" -ov
hdiutil verify "$dmg"
(cd macos/build && shasum -a 256 Sage-Keys-Apple-Silicon.dmg > DMG-SHA256.txt)
