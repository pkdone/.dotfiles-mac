#!/usr/bin/env bash
#
# Unit tests for lib/logi-settings.py (the read-only Logi Options+ check) against a
# synthetic settings.db built here — never the real one. Needs python3 (sqlite3 module);
# runs on Linux CI. Run: ./tests/logi-settings.test.sh  (exits non-zero on any failure)
#
set -uo pipefail   # deliberately not -e: run every assertion, then tally failures

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$DIR/lib/logi-settings.py"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "logi-settings tests: python3 not found, skipped"; exit 0; fi

pass=0
fail=0
eq() {  # description expected actual
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
has() {  # description needle haystack
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;; esac
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# make_db PATH [python statements tweaking dict d] — a settings.db shaped like the app's
make_db() {
  "$PY" - "$1" "${2:-pass}" <<'PY'
import json, sqlite3, sys
path, tweak = sys.argv[1], sys.argv[2]
p = "mx-master-3s-2b034"
def slot(s, card): return {"slotId": "%s_%s" % (p, s), "card": card}
d = {
  "schema_version": 26,
  "ever_connected_devices": {"devices": [
      {"deviceModel": "2b034", "slotPrefix": p, "serialNumber": "SERIAL-NOT-USED"}]},
  "profile_keys": ["profile-1"],
  "profile-1": {"name": "PROFILE_NAME_DEFAULT", "assignments": [
      slot("mouse_scroll_wheel_settings", {"mouseScrollWheelSettings": {
          "dir": "NATURAL", "isSmooth": True, "smartshift": {"isEnabled": True}}}),
      slot("thumb_wheel_adapter", {"name": "ASSIGNMENT_NAME_HORIZONTAL_SCROLL"}),
      slot("mouse_thumb_wheel_settings", {"mouseThumbWheelSettings": {"dir": "STANDARD", "isSmooth": True}}),
      slot("c195", {"selectedNestedCard": "window_navigation"}),
      slot("mouse_settings", {"mouseSettings": {"pointerSpeed": {"active": {"value": 0.13}}}}),
  ]},
  "settings_backup_state_v2": {"knownDevices": {"2b034": False}},
}
exec(tweak)
con = sqlite3.connect(path)
con.execute("CREATE TABLE data (_id INTEGER PRIMARY KEY, file BLOB)")
con.execute("CREATE TABLE snapshots (_id INTEGER PRIMARY KEY, uuid TEXT, label TEXT, file BLOB)")
con.execute("INSERT INTO data (file) VALUES (?)", (json.dumps(d).encode(),))
con.commit(); con.close()
PY
}
run() { "$PY" "$HELPER" "$@" 2>&1; }

# ---- all expected values present (pointer 0.13 is within the ±0.02 tolerance) ----
make_db "$tmp/good.db"
sum_before="$(cksum < "$tmp/good.db")"
out="$(run --db "$tmp/good.db")"; rc=$?
eq "only the backup flag is off -> rc 1" 1 "$rc"
eq "seven settings ok" 7 "$(printf '%s\n' "$out" | grep -c '^ok|')"
has "backup off is a warning" "warn|backup|" "$out"
has "snapshot count noted" "note|backup|0 settings snapshot(s)" "$out"
eq "source db unchanged (read from a copy)" "$sum_before" "$(cksum < "$tmp/good.db")"
mkdir "$tmp/t"; TMPDIR="$tmp/t" run --db "$tmp/good.db" >/dev/null
set -- "$tmp"/t/*
eq "temp copy deleted afterwards" "$tmp/t/*" "$1"
out="$(run --db "$tmp/good.db" --only wheel-smooth,thumb-smooth)"; rc=$?
eq "--only selects ids" "ok|wheel-smooth ok|thumb-smooth " "$(printf '%s\n' "$out" | cut -d'|' -f1,2 | tr '\n' ' ')"
eq "--only all ok -> rc 0" 0 "$rc"

# ---- found by model, not serial; slot-id fallback when the device list lacks it ----
make_db "$tmp/noserial.db" 'd["ever_connected_devices"] = {"devices": []}'
out="$(run --db "$tmp/noserial.db" --only wheel-natural)"; rc=$?
eq "slotId fallback by model" "0 ok|wheel-natural" "$rc $(printf '%s' "$out" | cut -d'|' -f1,2)"

# ---- drift ----
make_db "$tmp/drift.db" 'd["profile-1"]["assignments"][0]["card"]["mouseScrollWheelSettings"]["dir"] = "STANDARD"; d["profile-1"]["assignments"][4]["card"]["mouseSettings"]["pointerSpeed"]["active"]["value"] = 0.5; d["settings_backup_state_v2"]["knownDevices"]["2b034"] = True'
out="$(run --db "$tmp/drift.db")"; rc=$?
eq "drift -> rc 1" 1 "$rc"
has "direction drift" "drift|wheel-natural|Main wheel: scroll direction Natural — expected NATURAL, found STANDARD" "$out"
has "pointer outside tolerance" "drift|pointer-speed|Pointer speed 0.12 — expected 0.12 ±0.02, found 0.5" "$out"
has "backup on" "ok|backup|" "$out"
make_db "$tmp/gone.db" 'd["profile-1"]["assignments"] = d["profile-1"]["assignments"][:3]'
has "missing slot is drift" "drift|gesture-window-nav|" "$(run --db "$tmp/gone.db")"

# ---- missing / unreadable: error lines, never a traceback ----
out="$(run --db "$tmp/nope.db")"; rc=$?
eq "missing db -> rc 3" 3 "$rc"
has "missing db message" "error|-|settings.db not found" "$out"
printf 'not a database' > "$tmp/junk.db"
out="$(run --db "$tmp/junk.db")"; rc=$?
eq "junk db -> rc 2" 2 "$rc"
has "junk db message" "error|-|settings.db unreadable" "$out"
"$PY" -c 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute("CREATE TABLE data (file BLOB)"); c.execute("INSERT INTO data VALUES (?)", (b"{not json",)); c.commit()' "$tmp/badjson.db"
out="$(run --db "$tmp/badjson.db")"; rc=$?
eq "bad JSON -> rc 2" 2 "$rc"
has "bad JSON message" "error|-|settings.db unreadable" "$out"
out="$(run --db "$tmp/good.db" --only frobnicate)"; rc=$?
eq "unknown --only id -> rc 2" 2 "$rc"
eq "no traceback anywhere" 0 "$({ run --db "$tmp/junk.db"; run --db "$tmp/badjson.db"; run --db "$tmp/nope.db"; } | grep -c Traceback)"

# ---- the expected-values file itself ----
eq "expected-values file parses" "" "$(run --db "$tmp/good.db" | grep '^error')"
eq "every check.sh-required id listed" "backup gesture-window-nav pointer-speed smartshift thumb-horizontal thumb-smooth wheel-natural wheel-smooth " \
  "$(grep -Ev '^[[:space:]]*(#|$|model\|)' "$DIR/lib/logi-expected.list" | cut -d'|' -f1 | sort | tr '\n' ' ')"

rm -rf "$DIR/lib/__pycache__"
printf 'logi-settings tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
