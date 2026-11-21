#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
root="$PWD"
build="$root/macos/build"
evidence="$build/evidence"
actual="$build/install-check/Sage Keys.app"
qa="$build/Sage Keys QA.app"
mkdir -p "$evidence"
# Validate the ZIP after a Finder-compatible extraction, then launch its actual binary.
mkdir -p "$build/install-check"
ditto -x -k "$build/Sage-Keys-arm64.zip" "$build/install-check"
codesign --verify --deep --strict "$actual"
{ spctl --assess --type execute --verbose=3 "$actual" && echo "Gatekeeper accepted"; } > "$evidence/gatekeeper.txt" 2>&1 || echo "assessment exit $?" >> "$evidence/gatekeeper.txt"
codesign -dv --verbose=4 "$actual" >> "$evidence/gatekeeper.txt" 2>&1
"$actual/Contents/MacOS/SageKeys" > "$evidence/launch.log" 2>&1 &
release_pid=$!
sleep 4
ps -p "$release_pid" -o pid=,rss=,comm= > "$evidence/release-process.txt"
kill -TERM "$release_pid"
wait "$release_pid" || true
ditto "$actual" "$qa"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier io.github.annecat-bit.sagekeys.qa' "$qa/Contents/Info.plist"
xcrun swiftc -swift-version 5 -D SAGE_QA -O -target arm64-apple-macos13.0 macos/Sources/{PhysicalKeys,InstallationCheck,KeyMonitor,TrustedApps,SettingsLinks,GuideDrawing,PermissionGuide,PetWeb,PetApp}.swift macos/Tests/{GuideChecks,GuideExperience,DailyChecks,main}.swift -o "$qa/Contents/MacOS/SageKeys"
codesign --force --sign - --options runtime --timestamp=none "$qa"
xcrun swiftc macos/Tests/GuideAX/main.swift -o "$build/guide-ax"
python3 macos/Tests/processes.py "$evidence"
python3 macos/Tests/launch.py "$qa" "$evidence" "$root/macos/Tests/probe.js"
rm -f "$evidence/existing-webkit-pids" "$evidence/phase" "$evidence/qa-pid"
cat "$evidence/native-tests.log"
