#!/usr/bin/env bash
#
# Desktop picture check. Synthetic files only — the wallpaper store is not written.
# Run: ./tests/wallpaper-asset.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$DIR/lib/wallpaper-asset.py"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "wallpaper-asset tests: python3 not found, skipped"; exit 0; fi

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

ASSET="CF6347E2-4F81-4410-8892-4830991B6C5A"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf 'picture %s\n' "$ASSET" > "$tmp/hit.txt"
out="$("$PY" "$HELPER" --text "$tmp/hit.txt")"
eq "ascii asset id passes" "ok" "${out%%|*}"
has "pass names the picture" "Tahoe Night" "$out"

# UTF-16 LE, the way a binary plist often stores text.
"$PY" - "$tmp/utf16" "$ASSET" <<'PY'
import sys
open(sys.argv[1], "wb").write(sys.argv[2].encode("utf-16-le"))
PY
out="$("$PY" "$HELPER" --text "$tmp/utf16")"
eq "utf-16 asset id passes" "ok" "${out%%|*}"

printf 'other-picture\n' > "$tmp/miss.txt"
out="$("$PY" "$HELPER" --text "$tmp/miss.txt")"
eq "a different picture warns" "warn" "${out%%|*}"
has "a miss names the asset" "$ASSET" "$out"
has "a miss says fix will not change it" "does not change" "$out"

out="$("$PY" "$HELPER" --text "$tmp/missing-file")"
eq "a missing store warns" "warn" "${out%%|*}"
has "a missing store says so" "missing" "$out"

writers="$(grep -nE 'subprocess|os\.system|Popen' "$HELPER" || true)"
eq "helper does not shell out" "" "$writers"

printf 'wallpaper-asset tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
