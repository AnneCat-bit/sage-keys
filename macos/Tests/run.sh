#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
root="$PWD"
build="$root/macos/build"
evidence="$build/evidence"
actual="$build/Sage Keys.app"
qa="$build/Sage Keys QA.app"
mkdir -p "$evidence"
# Launch the actual packaged binary, independently of the instrumented QA build.
"$actual/Contents/MacOS/SageKeys" > "$evidence/launch.log" 2>&1 &
release_pid=$!
sleep 4
ps -p "$release_pid" -o pid=,rss=,comm= > "$evidence/release-process.txt"
kill -TERM "$release_pid"
wait "$release_pid" || true
ditto "$actual" "$qa"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier io.github.annecat-bit.sagekeys.qa' "$qa/Contents/Info.plist"
xcrun swiftc -swift-version 5 -D SAGE_QA -O -target arm64-apple-macos13.0 macos/Sources/{PhysicalKeys,KeyMonitor,PetWeb,PetApp}.swift macos/Tests/main.swift -o "$qa/Contents/MacOS/SageKeys"
codesign --force --sign - --options runtime --timestamp=none "$qa"
"$qa/Contents/MacOS/SageKeys" "$evidence" "$root/macos/Tests/probe.js" > "$evidence/native-tests.log" 2>&1 &
qa_pid=$!
trap 'kill "$qa_pid" 2>/dev/null || true' EXIT
echo 'phase,elapsed_seconds,host_cpu_percent,host_rss_kib' > "$evidence/process.csv"
start=$SECONDS
while kill -0 "$qa_pid" 2>/dev/null; do
  if (( SECONDS - start > 115 )); then echo "QA timeout"; cat "$evidence/native-tests.log"; exit 1; fi
  if [[ -s "$evidence/phase" ]]; then
    read -r cpu rss <<< "$(ps -p "$qa_pid" -o %cpu=,rss= || true)"
    [[ -z "$rss" ]] || echo "$(cat "$evidence/phase"),$((SECONDS-start)),$cpu,$rss" >> "$evidence/process.csv"
  fi
  sleep 0.5
done
result=0
wait "$qa_pid" || result=$?
trap - EXIT
cat "$evidence/native-tests.log"
exit "$result"
