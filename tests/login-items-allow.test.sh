#!/usr/bin/env bash
#
# Login-item allow-list and display names. Cursor and Cursor Nightly
# BackgroundActivityCheck agents must be allow-listed. A boolean name, which
# the BTM store sometimes holds and which prints as "true", must not be the
# name the check shows.
# Run: ./tests/login-items-allow.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "login-items-allow tests: python3 not found, skipped"; exit 0; fi

pass=0
fail=0
eq() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
has() {
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;; esac
}
miss() {
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n' "$1" "$2" ;;
    *) pass=$((pass + 1)) ;; esac
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

audit="$("$PY" - "$DIR/lib/btm-login-items.py" "$DIR/lib/login-items-allow.list" "$tmp/items.btm" <<'PY'
import importlib.util
import io
import plistlib
import sys
from contextlib import redirect_stdout
from pathlib import Path
mod_path, allow, dest = sys.argv[1:]
spec = importlib.util.spec_from_file_location("btm_login_items", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

def item(**kw):
    base = {
        "disposition": 0xB,  # enabled
        "type": 0x8,         # agent
        "name": "Example",
        "identifier": "8.com.example.agent",
        "bundleIdentifier": "",
        "developerName": "Example Dev",
        "teamIdentifier": "TEAMID",
        "url": "file:///bin",
        "executablePath": "",
        "container": "",
    }
    base.update(kw)
    return base

items = [
    item(
        name=True,
        identifier="8.com.todesktop.230313mzl4w4u92.BackgroundActivityCheck",
        bundleIdentifier="com.todesktop.230313mzl4w4u92",
        developerName="Anysphere, Inc.",
        teamIdentifier="VDXQ22DGB9",
        executablePath="/Applications/Cursor.app/Contents/Library/LoginItems/BackgroundActivityCheck",
    ),
    item(
        name="true",
        identifier="co.anysphere.cursor.nightly.BackgroundActivityCheck",
        bundleIdentifier="",
        developerName="Anysphere, Inc.",
        executablePath="/Applications/Cursor Nightly.app/Contents/Library/LoginItems/BackgroundActivityCheck",
    ),
    item(
        name=True,
        identifier="8.com.example.other",
        bundleIdentifier="com.todesktop.230313mzl4w4u92.BackgroundActivityCheck",
        executablePath="/Applications/Cursor.app/Contents/Library/LoginItems/BackgroundActivityCheck",
    ),
    item(
        name="Helper",
        identifier="8.com.unrelated.helper",
        bundleIdentifier="",
        container="2.co.anysphere.cursor.nightly",
        executablePath="/Applications/Cursor Nightly.app/Contents/MacOS/Helper",
    ),
    item(
        name="pin-dictation",
        identifier="8.com.pdone.pin-dictation-hotkey-164",
        bundleIdentifier="",
    ),
    item(
        name="Raycast",
        identifier="2.com.raycast.macos",
        bundleIdentifier="com.raycast.macos",
        executablePath="/Applications/Raycast.app/Contents/MacOS/Raycast",
    ),
    item(
        name="Widget",
        identifier="8.com.evil.widget",
        bundleIdentifier="com.evil.widget",
    ),
]
plistlib.dump({
    "$version": 100000,
    "$archiver": "NSKeyedArchiver",
    "$top": {"root": "items"},
    "$objects": ["$null"] + items,
}, open(dest, "wb"))

buf = io.StringIO()
with redirect_stdout(buf):
    mod.audit(allow, None, [Path(dest)])
sys.stdout.write(buf.getvalue())
PY
)" || { echo "login-items-allow tests: audit helper failed"; exit 1; }

# class|kind|name|developer|team|id|detail
field() { # needle, field number (1-based)
  printf '%s\n' "$audit" | awk -F'|' -v id="$1" -v n="$2" 'index($0, id) { print $n; exit }'
}

eq "cursor helper display name" BackgroundActivityCheck "$(field "com.todesktop.230313mzl4w4u92|" 3)"
eq "cursor helper class" allow "$(field "com.todesktop.230313mzl4w4u92|" 1)"

eq "nightly helper class" allow "$(field "co.anysphere.cursor.nightly.BackgroundActivityCheck" 1)"
eq "nightly helper display name" BackgroundActivityCheck "$(field "co.anysphere.cursor.nightly.BackgroundActivityCheck" 3)"
miss "nightly name is not the word true" "|true|" "$(printf '%s\n' "$audit" | grep 'cursor.nightly.BackgroundActivityCheck')"

eq "helper bundle id is allow-listed" allow "$(field "com.todesktop.230313mzl4w4u92.BackgroundActivityCheck" 1)"
eq "helper inside nightly is allow-listed" allow "$(field "com.unrelated.helper" 1)"
eq "real helper name is kept" Helper "$(field "com.unrelated.helper" 3)"

eq "dictation pin label still allow-listed" allow "$(field "com.pdone.pin-dictation-hotkey-164" 1)"
eq "raycast name stays Raycast" Raycast "$(field "com.raycast.macos" 3)"
eq "raycast stays allow-listed" allow "$(field "com.raycast.macos" 1)"

eq "unknown item stays unknown" unknown "$(field "com.evil.widget" 1)"
eq "unknown item keeps its name" Widget "$(field "com.evil.widget" 3)"

has "allow list mentions Cursor BackgroundActivityCheck" \
  "com.todesktop.230313mzl4w4u92.BackgroundActivityCheck" "$(cat "$DIR/lib/login-items-allow.list")"
has "allow list mentions Cursor Nightly" \
  "co.anysphere.cursor.nightly" "$(cat "$DIR/lib/login-items-allow.list")"

printf 'login-items-allow tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
