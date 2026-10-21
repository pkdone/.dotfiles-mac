#!/usr/bin/env bash
#
# Spotlight Results from Apps: the 13 names in lib/spotlight-apps.list, and
# how EnabledPreferenceRules is compared. Nothing is written.
# Run: ./tests/spotlight-rules.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$DIR/lib/spotlight-rules.py"
LIST="$DIR/lib/spotlight-apps.list"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "spotlight-rules tests: python3 not found, skipped"; exit 0; fi

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

names="$(awk -F'|' '$1 !~ /^#/ && NF { print $1 }' "$LIST" | tr '\n' ',' | sed 's/,$//')"
eq "thirteen apps" "Books,Keynote,Mail,Notes,Numbers,Photos,Podcasts,Reminders,Safari,Shortcuts,Stocks,Tips,Voice Memos" "$names"

run() { "$PY" "$HELPER" --list "$LIST" --json "$1"; }

out="$(run '["com.apple.finder","com.apple.Safari.something-else"]')"
eq "other apps on is ok" "ok" "${out%%|*}"

out="$(run '["com.apple.mail"]')"
eq "Mail on is a warning" "warn" "${out%%|*}"
has "Mail on names Mail" "Mail" "$out"

all_off="$("$PY" - "$LIST" <<'PY'
import json, sys
apps = []
for raw in open(sys.argv[1], encoding="utf-8"):
    line = raw.split("#", 1)[0].strip()
    if not line or "|" not in line:
        continue
    _name, bundle = line.split("|", 1)
    apps.append((bundle.strip(), 0))
print(json.dumps(dict(apps)))
PY
)"
out="$(run "$all_off")"
eq "every listed app explicitly off passes" "ok" "${out%%|*}"

out="$(run '{"com.apple.finder": 1}')"
eq "enabled-only map with Mail absent is ok" "ok" "${out%%|*}"

out="$(run '{"com.apple.mail": 1, "com.apple.Safari": 0}')"
eq "Mail on inside a mixed map warns" "warn" "${out%%|*}"

out="$(run '[{"bundleID": "com.apple.mail", "enabled": true}]')"
eq "dict list with Mail enabled warns" "warn" "${out%%|*}"

out="$(run '[{"name": "Books", "enabled": false}, {"bundleID": "com.apple.mail", "enabled": 0}]')"
eq "a partial off list is not a silent pass" "warn" "${out%%|*}"
has "a partial off list names what is missing" "not listed as off" "$out"

out="$(run '12')"
eq "a number is not a silent pass" "warn" "${out%%|*}"
has "a number says the shape is not understood" "does not understand" "$out"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
"$PY" - "$tmp" <<'PY'
import plistlib, sys
plistlib.dump({"Other": 1}, open(sys.argv[1], "wb"))
PY
out="$("$PY" "$HELPER" --list "$LIST" --plist "$tmp")"
eq "missing key warns" "warn" "${out%%|*}"
has "missing key names the preference" "EnabledPreferenceRules is not set" "$out"

eq "manual step uses the spotlight check" "spotlight-results" \
  "$(awk -F'|' '$1=="spotlight-results" { print $6; exit }' "$DIR/lib/manual-steps.list")"

printf 'spotlight-rules tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
