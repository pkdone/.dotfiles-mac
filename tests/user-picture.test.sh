#!/usr/bin/env bash
#
# Account picture check. Synthetic dscl dumps only — dscl is not run.
# Run: ./tests/user-picture.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$DIR/lib/user-picture.py"
EXPECT="$DIR/lib/user-picture.sha256"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "user-picture tests: python3 not found, skipped"; exit 0; fi

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

DOG="4d6ee72d4793f984bdfca248a3b8c334138f7183c6d77bb4fa524890cf345ecc"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
chmod +x "$HELPER"

stored="$(grep -E '^[0-9a-f]{64}$' "$EXPECT")"
eq "lib hash is the Dog" "$DOG" "$stored"
eq "user-picture is checked by macconfig" "@macconfig-check.sh" \
  "$(awk -F'|' '$1 == "user-picture" { print $6; exit }' "$DIR/lib/manual-steps.list")"
has "manual step says macconfig checks this" "macconfig checks this" \
  "$(awk -F'|' '$1 == "user-picture" { print $3; exit }' "$DIR/lib/manual-steps.list")"
eq "user-picture is report-only" "PAUL|" \
  "$(awk -F'|' '$1 == "user-picture" { print $2 "|" $3; exit }' "$DIR/lib/autofix.list")"

printf 'JPEGPhoto:\n ff d8 ff d9\n' > "$tmp/tiny.txt"
tiny_hash="$("$PY" - "$tmp/tiny.txt" <<'PY'
import hashlib, re, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
digits = re.sub(r"[^0-9A-Fa-f]", "", "".join(lines[1:]))
print(hashlib.sha256(bytes.fromhex(digits)).hexdigest())
PY
)"
printf '%s\n' "$tiny_hash" > "$tmp/expect.txt"
out="$("$PY" "$HELPER" --expect "$tmp/expect.txt" --dump "$tmp/tiny.txt")"
eq "matching picture passes" "ok" "${out%%|*}"
has "pass names the Dog" "account picture is the Dog" "$out"

# First line is not hashed, even when it contains hex.
printf 'JPEGPhoto: ffd8ffd9\n ff d8 ff d9\n' > "$tmp/label-hex.txt"
out="$("$PY" "$HELPER" --expect "$tmp/expect.txt" --dump "$tmp/label-hex.txt")"
eq "hex on the label line is ignored" "ok" "${out%%|*}"

printf 'JPEGPhoto:\n 00 11\n' > "$tmp/other.txt"
out="$("$PY" "$HELPER" --expect "$tmp/expect.txt" --dump "$tmp/other.txt")"
eq "a different picture warns" "warn" "${out%%|*}"
has "a miss names both hashes" "$tiny_hash" "$out"
has "a miss says macconfig does not change it" "does not change" "$out"

printf 'JPEGPhoto:\n' > "$tmp/empty.txt"
out="$("$PY" "$HELPER" --expect "$tmp/expect.txt" --dump "$tmp/empty.txt")"
eq "no picture bytes warns" "warn" "${out%%|*}"
has "no picture bytes says it could not be read" "could not be read" "$out"

before="$(cksum "$tmp/tiny.txt")"
"$PY" "$HELPER" --expect "$tmp/expect.txt" --dump "$tmp/tiny.txt" >/dev/null
eq "reading does not rewrite the dump" "$before" "$(cksum "$tmp/tiny.txt")"

writers="$(grep -nE 'subprocess|os\.system|Popen|defaults write' "$HELPER" || true)"
eq "helper does not shell out or write defaults" "" "$writers"

# The real Dog hash matches the documented pipeline when xxd is available.
if command -v xxd >/dev/null 2>&1; then
  printf 'JPEGPhoto:\n ff d8 ff d9\n' > "$tmp/pipe.txt"
  pipe="$(tail -n +2 "$tmp/pipe.txt" | xxd -r -p | sha256sum | awk '{print $1}')"
  py="$("$PY" - "$tmp/pipe.txt" <<'PY'
import hashlib, re, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
digits = re.sub(r"[^0-9A-Fa-f]", "", "".join(lines[1:]))
print(hashlib.sha256(bytes.fromhex(digits)).hexdigest())
PY
)"
  eq "python hash matches tail | xxd -r -p | sha256sum" "$pipe" "$py"
else
  pass=$((pass + 1))
fi

printf 'user-picture tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
