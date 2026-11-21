#!/bin/bash
# Compare two unmodified, already packaged releases in an isolated installation path.
set -euo pipefail
old_zip=$1
new_zip=$2
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/Applications" "$scratch/update"
ditto -x -k "$old_zip" "$scratch/Applications"
ditto -x -k "$new_zip" "$scratch/update"
app="$scratch/Applications/Sage Keys.app"
describe() {
  codesign --verify --deep --strict "$app"
  codesign -d -r- --verbose=3 "$app" 2>&1 | awk '/^(Identifier=|TeamIdentifier=|Signature=|CDHash=|.*designated =>)/'
}
xcrun swiftc macos/Tests/GuideCost/main.swift -o "$scratch/guide-cost"
describe
"$scratch/guide-cost" "$app"
old_req=$(codesign -d -r- "$app" 2>&1 | sed -n 's/^.*designated => //p')
test -n "$old_req"
codesign --verify -R="$old_req" "$app"
mv "$app" "$scratch/previous.app"
mv "$scratch/update/Sage Keys.app" "$app"
describe
"$scratch/guide-cost" "$app"
if codesign --verify -R="$old_req" "$app"; then
  echo 'New build satisfies previous designated requirement at identical installation path.'
else
  echo 'New build fails previous designated requirement at identical installation path.'
fi
