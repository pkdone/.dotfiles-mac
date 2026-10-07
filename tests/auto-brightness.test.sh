#!/usr/bin/env bash
#
# Unit tests for lib/auto-brightness.py. Synthetic plists only — never
# corebrightnessdiag or the root CoreBrightness plist.
# Run: ./tests/auto-brightness.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$DIR/lib/auto-brightness.py"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "auto-brightness tests: python3 not found, skipped"; exit 0; fi

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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
chmod +x "$HELPER"

# write_plist PATH python — p is the object dumped as XML
write_plist() {
  "$PY" - "$1" "$2" <<'PY'
import plistlib, sys
path, expr = sys.argv[1], sys.argv[2]
p = eval(expr)
with open(path, "wb") as fh:
    plistlib.dump(p, fh, fmt=plistlib.FMT_XML)
PY
}
run() { "$PY" "$HELPER" --plist "$1"; }

write_plist "$tmp/on.plist" '{
  "CBAutoBrightnessEnabled": True,
  "DisplayBrightnessAuto": 1,
  "CBColorAdaptationEnabled": True,
}'
out="$(run "$tmp/on.plist")"; rc=$?
eq "on exits 0" 0 "$rc"
eq "both on is drift" "bad||Automatically adjust brightness is on (CBAutoBrightnessEnabled=true, DisplayBrightnessAuto=1) — System Settings → Displays → turn it off. check.sh --fix does not change this (the CoreBrightness plist is root-owned; True Tone and Slightly dim the display on battery are left alone)" "$out"

write_plist "$tmp/off.plist" '{
  "displays": [
    {"name": "Built-in", "CBAutoBrightnessEnabled": False, "DisplayBrightnessAuto": 0,
     "CBColorAdaptationEnabled": True},
  ],
  "KeyboardAutoBrightness": True,
}'
out="$(run "$tmp/off.plist")"; rc=$?
eq "off exits 0" 0 "$rc"
eq "nested off is ok and ignores True Tone" "ok||Automatically adjust brightness is off (CBAutoBrightnessEnabled=false, DisplayBrightnessAuto=0)" "$out"

write_plist "$tmp/split.plist" '{
  "panel": {"CBAutoBrightnessEnabled": False},
  "other": {"DisplayBrightnessAuto": 1},
}'
out="$(run "$tmp/split.plist")"
has "one key still on is drift" "bad||Automatically adjust brightness is on (CBAutoBrightnessEnabled=false, DisplayBrightnessAuto=1)" "$out"

write_plist "$tmp/external.plist" '{
  "displays": [
    {"CBAutoBrightnessEnabled": False, "DisplayBrightnessAuto": 0},
    {"CBAutoBrightnessEnabled": True, "DisplayBrightnessAuto": 0},
  ]
}'
out="$(run "$tmp/external.plist")"
has "any display still on is drift" "CBAutoBrightnessEnabled=false/true" "$out"
has "external on is bad" "bad||" "$out"

write_plist "$tmp/empty.plist" '{"CBColorAdaptationEnabled": True, "lessbright": 1}'
out="$(run "$tmp/empty.plist")"
eq "unrelated keys are not a pass" "warn||status-info has no CBAutoBrightnessEnabled or DisplayBrightnessAuto — can't tell if Automatically adjust brightness is on" "$out"

printf 'not a plist\n' > "$tmp/bad.plist"
out="$(run "$tmp/bad.plist")"; rc=$?
eq "garbage exits 0" 0 "$rc"
has "garbage is a warning" "warn||could not read corebrightnessdiag status-info" "$out"

# Leading log noise, the way a diag tool can print before the plist.
"$PY" - "$tmp/wrapped.plist" <<'PY'
import plistlib, sys
body = plistlib.dumps({"CBAutoBrightnessEnabled": False, "DisplayBrightnessAuto": 0}, fmt=plistlib.FMT_XML)
open(sys.argv[1], "wb").write(b"corebrightnessdiag status-info\n" + body)
PY
out="$(run "$tmp/wrapped.plist")"
eq "plist after a header still parses" "ok||Automatically adjust brightness is off (CBAutoBrightnessEnabled=false, DisplayBrightnessAuto=0)" "$out"

stdin_out="$("$PY" "$HELPER" < "$tmp/off.plist")"
eq "stdin matches --plist" "ok||Automatically adjust brightness is off (CBAutoBrightnessEnabled=false, DisplayBrightnessAuto=0)" "$stdin_out"

printf 'auto-brightness tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
