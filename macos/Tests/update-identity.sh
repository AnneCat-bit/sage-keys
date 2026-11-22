#!/bin/bash
# Two downloaded release ZIPs in a disposable ARM runner. Refuse to replace any pre-existing installation.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]]
old_zip=$1
new_zip=$2
scratch=$(mktemp -d)
app="/Applications/Sage Keys.app"
trap 'rm -rf "$scratch"' EXIT
[[ ! -e "$app" && ! -L "$app" ]]
mkdir "$scratch/old-download" "$scratch/new-download"
ditto -x -k "$old_zip" "$scratch/old-download"
ditto -x -k "$new_zip" "$scratch/new-download"
old="$scratch/old-download/Sage Keys.app"
new="$scratch/new-download/Sage Keys.app"
for release in "$old" "$new"; do
  codesign --verify --deep --strict "$release"
  codesign -d -r- --verbose=3 "$release" 2>&1 | awk '/^(Identifier=|TeamIdentifier=|Signature=|CDHash=|.*designated =>)/'
done
old_req=$(codesign -d -r- "$old" 2>&1 | sed -n 's/^.*designated => //p')
old_hash=$(codesign -dv --verbose=4 "$old" 2>&1 | sed -n 's/^CDHash=//p')
test -n "$old_req"
test -n "$old_hash"
codesign --verify -R="$old_req" "$old"
xcrun swiftc macos/Tests/ReleaseLifecycle/main.swift -o "$scratch/release-lifecycle"
mv "$old" "$app"
trap 'rm -rf "$app" "$scratch"' EXIT
"$scratch/release-lifecycle" "$app" "$new" "$scratch/previous.app" "$old_hash"
if codesign --verify -R="$old_req" "$app"; then
  echo 'New release satisfies the old designated requirement.'
else
  echo 'New release does not satisfy the old designated requirement at the same path.'
fi
