#!/usr/bin/env bash
#
# Tests for the multi-line summary at the end of check.sh. The summary block is cut out
# of check.sh (between "# ---- summary" and "# ---- --issues") and run with stub counts,
# so nothing macOS-specific executes. Plain bash; runs on Linux CI and macOS bash 3.2.
# Run: ./tests/check-summary.test.sh   (exits non-zero if any assertion fails)
#
set -uo pipefail   # deliberately not -e: run every assertion, then tally failures

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLOCK="$(awk '/^# ---- summary ---/ {on = 1} /^# ---- --issues/ {on = 0} on' "$DIR/check.sh")"

pass=0
fail=0
eq() {  # description expected actual
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}

# render CHECKED OKS DRIFT WARN HAND FIX DRY_RUN AFTER_DRIFT AFTER_WARN NFIXED NPAUL NWOULD [ITEM-ID...]
# shellcheck disable=SC2034  # the stub variables are read by the eval'd check.sh block
render() {
  (
    set -eu
    DOTDIR="$DIR"; US=$'\037'
    C_OK=''; C_BAD=''; C_WARN=''; C_HDR=''; C_DIM=''; C_OFF=''
    CHECKED=$1; OKS=$2; DRIFT=$3; WARN=$4; HAND=$5; FIX=$6; DRY_RUN=$7
    AFTER_DRIFT=$8; AFTER_WARN=$9; shift 9
    FIXED=(); NEEDS_PAUL=(); WOULD_FIX=(); FIX_ITEMS=()
    i=0; while [ "$i" -lt "$1" ]; do FIXED+=(x); i=$((i + 1)); done
    i=0; while [ "$i" -lt "$2" ]; do NEEDS_PAUL+=(x); i=$((i + 1)); done
    i=0; while [ "$i" -lt "$3" ]; do WOULD_FIX+=(x); i=$((i + 1)); done
    shift 3
    for id in "$@"; do FIX_ITEMS+=("drift${US}${id}${US}${US}msg"); done
    eval "$BLOCK"
  ) 2>&1
}

eq "all good" "
Summary
  ✔ ok           139 / 139
  ✖ drift          0
  ⚠ warnings       0
  ✋ by hand      20   (scripts/manual-steps.sh list)
  All good" "$(render 139 139 0 0 20 0 0 0 0 0 0 0)"

eq "drift + warning, two of them SAFE" "
Summary
  ✔ ok           136 / 139
  ✖ drift          2
  ⚠ warnings       1
  ✋ by hand      20   (scripts/manual-steps.sh list)
  → run ./check.sh --fix to repair 2 safe item(s)
  3 need attention (2 drift, 1 warning)" \
  "$(render 139 136 2 1 20 0 0 2 1 0 0 0 defaults symlink brew)"

eq "single warning, nothing SAFE" "  1 needs attention (1 warning)" \
  "$(render 139 138 0 1 20 0 0 0 1 0 0 0 dotfiles-git | tail -1)"
eq "no fix hint when nothing is SAFE" "" "$(render 139 138 0 1 20 0 0 0 1 0 0 0 dotfiles-git | grep -F 'check.sh --fix')"

eq "--fix: fixed + needs Paul, drift before/after" "
Summary
  ✔ ok           137 / 139
  ✖ drift          0   (was 1 before --fix)
  ⚠ warnings       1
  ✋ by hand      20   (scripts/manual-steps.sh list)
  ↻ fixed          1
  ☞ needs Paul     1
  1 needs attention (1 warning)" "$(render 139 137 1 1 20 1 0 0 1 1 1 0 defaults brew)"

eq "--fix --dry-run: would fix" "  ↻ would fix      1   (dry run: nothing changed)" \
  "$(render 139 138 1 0 20 1 1 1 0 0 0 1 defaults | grep 'would fix')"

eq "check.sh no longer prints the old one-line summary" "" \
  "$(grep -n 'checked, %d ok, %d drift' "$DIR/check.sh")"

printf 'check-summary tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
