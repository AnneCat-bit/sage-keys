#!/bin/bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]]
cd "$(dirname "$0")/../.."
app="/Applications/Sage Keys.app"
mount="$PWD/macos/build/dmg-check"
[[ ! -e "$app" && ! -L "$app" ]]
mkdir -p "$mount"
hdiutil attach macos/build/Sage-Keys-Apple-Silicon.dmg -mountpoint "$mount" -readonly -nobrowse
trap 'hdiutil detach "$mount" >/dev/null 2>&1 || true; rm -rf "$app"' EXIT
[[ "$(readlink "$mount/Applications")" == /Applications ]]
codesign --verify --deep --strict "$mount/Sage Keys.app"
xcrun swiftc macos/Tests/DMG/main.swift -o macos/build/dmg-check-tool
macos/build/dmg-check-tool "$mount" "$PWD/macos/build/evidence" | tee macos/build/evidence/dmg-lifecycle.log
codesign --verify --deep --strict "$app"
python3 - <<'PY'
from pathlib import Path
import hashlib,json,os
def manifest(root):
    result={}
    for p in root.rglob('*'):
        name=str(p.relative_to(root))
        if p.is_symlink():result[name]=['link',os.readlink(p)]
        elif p.is_file():result[name]=['file',hashlib.sha256(p.read_bytes()).hexdigest(),p.stat().st_mode & 0o777]
    return result
original=manifest(Path('macos/build/Sage Keys.app'))
installed=manifest(Path('/Applications/Sage Keys.app'))
assert original==installed
Path('macos/build/evidence/dmg-integrity.json').write_text(json.dumps({'files':len(original),'identicalContentModesAndSymlinks':True,'source':original},indent=2))
print('PASS installed app matches every compiled file, file mode and symlink')
PY
[[ ! -e "$mount/Sage Keys.app" ]]
