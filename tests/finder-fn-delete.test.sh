#!/usr/bin/env bash
#
# Finder Fn+Delete moves the selected item to the Bin. The built-in keyboard
# has no Forward Delete key, and Karabiner does not feed a generated
# delete_forward back through later rules, so the Finder mapping has to sit
# in the Fn layer, ahead of the generic Fn+Delete -> delete_forward
# manipulator. A real Forward Delete key still uses the later Finder rule.
# Reads the repo JSON and the shortcut docs only. Run: ./tests/finder-fn-delete.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KJ="$DIR/karabiner/karabiner.json"
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

order="$(python3 - "$KJ" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    print("invalid-json")
    raise SystemExit(0)

if not isinstance(data, dict):
    print("not-an-object")
    raise SystemExit(0)

rules = []
for profile in data.get("profiles") or []:
    if not isinstance(profile, dict):
        continue
    mods = profile.get("complex_modifications") or {}
    if not isinstance(mods, dict):
        continue
    found = mods.get("rules") or []
    if isinstance(found, list):
        rules.extend(r for r in found if isinstance(r, dict))

fn_rules = [
    r for r in rules
    if str(r.get("description") or "").startswith(
        "Never start Dictation/Siri from Fn/Globe"
    )
]
if len(fn_rules) != 1:
    print("fn-rule-count=%d" % len(fn_rules))
    raise SystemExit(0)

finder = {
    "type": "basic",
    "from": {
        "key_code": "delete_or_backspace",
        "modifiers": {"optional": ["any"]},
    },
    "to": [{"key_code": "delete_or_backspace", "modifiers": ["left_command"]}],
    "conditions": [
        {"type": "variable_if", "name": "pdone_fn", "value": 1},
        {
            "type": "frontmost_application_if",
            "bundle_identifiers": ["^com\\.apple\\.finder$"],
        },
    ],
}
generic = {
    "type": "basic",
    "from": {
        "key_code": "delete_or_backspace",
        "modifiers": {"optional": ["any"]},
    },
    "to": [{"key_code": "delete_forward"}],
    "conditions": [{"type": "variable_if", "name": "pdone_fn", "value": 1}],
}
external = {
    "type": "basic",
    "from": {
        "key_code": "delete_forward",
        "modifiers": {"optional": ["any"]},
    },
    "to": [{"key_code": "delete_or_backspace", "modifiers": ["left_command"]}],
    "conditions": [
        {
            "type": "frontmost_application_if",
            "bundle_identifiers": ["^com\\.apple\\.finder$"],
        }
    ],
}

manips = fn_rules[0].get("manipulators") or []
if not isinstance(manips, list):
    print("fn-manipulators-not-a-list")
    raise SystemExit(0)
finder_at = [i for i, m in enumerate(manips) if m == finder]
generic_at = [i for i, m in enumerate(manips) if m == generic]
if len(finder_at) != 1:
    print("finder-fn-delete-count=%d" % len(finder_at))
    raise SystemExit(0)
if len(generic_at) != 1:
    print("generic-fn-delete-count=%d" % len(generic_at))
    raise SystemExit(0)
if finder_at[0] >= generic_at[0]:
    print("order finder=%d generic=%d" % (finder_at[0], generic_at[0]))
    raise SystemExit(0)

ext_rules = [
    r for r in rules
    if r.get("description") == "Finder: Forward Delete -> Move to Trash"
    and r.get("enabled") is True
    and r.get("manipulators") == [external]
]
if len(ext_rules) != 1:
    print("external-forward-delete-count=%d" % len(ext_rules))
    raise SystemExit(0)

print("ok")
PY
)" || order="python-failed"
eq "Finder Fn+Delete manipulator is before generic Fn+Delete" ok "$order"

shortcuts="$(cat "$DIR/SHORTCUTS.md")"
has "shortcuts say Fn+Delete moves the item to the Bin" \
  "| Move selected item to the Bin | Fn + Delete (or Forward Delete on an external keyboard) in Finder |" \
  "$shortcuts"
miss "shortcuts no longer say only a Forward Delete key in Finder" \
  "Forward Delete (in Finder; mapped to Move to Trash)" \
  "$shortcuts"

settings="$(cat "$DIR/docs/settings.md")"
has "settings say Fn+Delete in Finder moves the item to the Bin" \
  "in Finder moves the selected item to the Bin" \
  "$settings"
has "settings keep Forward Delete on an external keyboard" \
  "Forward Delete on an external keyboard in Finder also moves the selected item to the Bin" \
  "$settings"
miss "settings no longer describe only Finder Forward Delete" \
  "Finder Forward Delete" \
  "$settings"

printf 'finder-fn-delete tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
