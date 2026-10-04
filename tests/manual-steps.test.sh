#!/usr/bin/env bash
#
# Unit tests for scripts/manual-steps.sh's list parser (lib/manual-steps.list).
# Plain bash, no framework; runs on Linux CI too (list/validate don't touch macOS).
# Run: ./tests/manual-steps.test.sh   (exits non-zero if any assertion fails)
#
set -uo pipefail   # deliberately not -e: run every assertion, then tally failures

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MS="$DIR/../scripts/manual-steps.sh"
LIST="$DIR/../lib/manual-steps.list"
export NO_COLOR=1

pass=0
fail=0
eq() {  # DESCRIPTION EXPECTED ACTUAL
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"
  fi
}
has() {  # DESCRIPTION NEEDLE HAYSTACK
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n' "$1" "$2" ;;
  esac
}

# ---- the real list is well-formed -----------------------------------------
out="$("$MS" validate 2>&1)"; rc=$?
eq "real list validates" 0 "$rc"
[ "$rc" -eq 0 ] || printf '%s\n' "$out"

rows="$(grep -cEv '^[[:space:]]*(#|$)' "$LIST")"
listed="$("$MS" list | grep -cE '^ +[0-9]+\. ')"
eq "list prints one numbered line per row" "$rows" "$listed"

nums="$("$MS" list | sed -nE 's/^ +([0-9]+)\. .*/\1/p' | tr '\n' ' ')"
eq "numbering is 1..N with no gaps" "$(seq 1 "$rows" | tr '\n' ' ')" "$nums"

md_rows="$("$MS" list --markdown | grep -cE '^\| [0-9]+ \|')"
eq "markdown has one row per step" "$rows" "$md_rows"

# README's table must match the list (refresh: scripts/manual-steps.sh list --markdown).
readme_rows="$(grep -E '^\| [0-9]+ \|' "$DIR/../README.md")"
eq "README manual-steps table matches lib/manual-steps.list" \
  "$("$MS" list --markdown | grep -E '^\| [0-9]+ \|')" "$readme_rows"

# ---- malformed rows are reported ------------------------------------------
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<'ROWS'
# comment line
good-one|Group A|Title|Where||
good-two|Group A|Title|Where|x-apple.systempreferences:com.apple.Trackpad-Settings.extension|defaults:com.apple.AppleMultitouchTrackpad:Clicking=1
good-one|Group A|Duplicate id|Where||
Bad_Id|Group A|Title|Where||
too-many|Group A|Title|Where|||extra
no-title|Group A||Where||
bad-open|Group A|Title|Where|ftp://nope|
bad-check|Group A|Title|Where||frobnicate
bad-tcc|Group A|Title|Where||tcc:Accessibility:com.evil';drop
split|Group B|Title|Where||
split-2|Group A|Title|Where||app:Finder
ROWS
out="$(MANUAL_STEPS_LIST="$tmp" "$MS" validate 2>&1)"; rc=$?
eq "malformed list fails validate" 1 "$rc"
has "duplicate id"      "duplicate id 'good-one'" "$out"
has "kebab-case id"     "id 'Bad_Id' must be kebab-case" "$out"
has "too many fields"   "too many fields" "$out"
has "required fields"   "id, group, title and where are required" "$out"
has "bad open target"   "open 'ftp://nope'" "$out"
has "unknown check"     "unknown check 'frobnicate'" "$out"
has "unsafe tcc spec"   "unknown check 'tcc:Accessibility:com.evil';drop'" "$out"
has "split group"       "group 'Group A' is split" "$out"

# Bad rows are skipped (with a warning) so list still prints the good ones.
good="$(MANUAL_STEPS_LIST="$tmp" "$MS" list 2>/dev/null | grep -cE '^ +[0-9]+\. ')"
eq "list skips rows with missing/extra fields" 9 "$good"

printf 'manual-steps tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
