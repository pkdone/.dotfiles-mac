#!/usr/bin/env bash
#
# Tests for the multi-line summary at the end of macconfig-check.sh. The summary block is cut out
# of macconfig-check.sh (between "# ---- summary" and "# ---- --issues") and run with stub counts,
# so nothing macOS-specific executes. Plain bash; runs on Linux CI and macOS bash 3.2.
# Run: ./tests/check-summary.test.sh   (exits non-zero if any assertion fails)
#
set -uo pipefail   # deliberately not -e: run every assertion, then tally failures

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLOCK="$(awk '/^# ---- summary ---/ {on = 1} /^# ---- --issues/ {on = 0} on' "$DIR/macconfig-check.sh")"

pass=0
fail=0
eq() {  # description expected actual
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}

# render CHECKED OKS DRIFT WARN HAND FIX DRY_RUN AFTER_DRIFT AFTER_WARN NFIXED NPAUL NWOULD [ITEM-ID...]
# Attention bullets come from T_ATTN (and T_RECHECK when T_RECHECK_RAN=1), each
# "kind US section US id US message". T_COLOR=1 turns the summary colours on;
# the default is plain text, which is what --no-color / NO_COLOR / a pipe produce.
# shellcheck disable=SC2034  # the stub variables are read by the eval'd macconfig-check.sh block
render() {
  (
    set -eu
    DOTDIR="$DIR"; US=$'\037'
    if [ "${T_COLOR:-0}" = 1 ]; then
      C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_WARN=$'\033[33m'; C_HDR=$'\033[1m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
    else
      C_OK=''; C_BAD=''; C_WARN=''; C_HDR=''; C_DIM=''; C_OFF=''
    fi
    CHECKED=$1; OKS=$2; DRIFT=$3; WARN=$4; HAND=$5; FIX=$6; DRY_RUN=$7
    AFTER_DRIFT=$8; AFTER_WARN=$9; shift 9
    FIXED=(); NEEDS_PAUL=(); WOULD_FIX=(); FIX_ITEMS=()
    ATTN_ITEMS=(); RECHECK_ITEMS=(); ATTN_LINES=()
    RECHECK_RAN=${T_RECHECK_RAN:-0}
    for x in ${T_ATTN[@]+"${T_ATTN[@]}"}; do ATTN_ITEMS+=("$x"); done
    for x in ${T_RECHECK[@]+"${T_RECHECK[@]}"}; do RECHECK_ITEMS+=("$x"); done
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
  → run ./macconfig-check.sh --fix to repair 2 safe item(s)
  3 need attention (2 drift, 1 warning)" \
  "$(render 139 136 2 1 20 0 0 2 1 0 0 0 defaults symlink brew)"

eq "single warning, nothing SAFE" "  1 needs attention (1 warning)" \
  "$(render 139 138 0 1 20 0 0 0 1 0 0 0 dotfiles-git | tail -1)"
eq "no fix hint when nothing is SAFE" "" "$(render 139 138 0 1 20 0 0 0 1 0 0 0 dotfiles-git | grep -F 'macconfig-check.sh --fix')"

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

eq "macconfig-check.sh no longer prints the old one-line summary" "" \
  "$(grep -n 'checked, %d ok, %d drift' "$DIR/macconfig-check.sh")"

# Attention bullets. US separates kind / section / id / message, same as macconfig-check.sh.
US=$'\037'
DRIFT_ITEM="drift${US}Symlinks${US}symlink${US}~/.gitconfig -> elsewhere (expected repo)"
WARN_ITEM="warn${US}Mac health${US}health${US}disk: only 12 GB free (8%) on Data"
T_ATTN=("$DRIFT_ITEM" "$WARN_ITEM")
attn_out="$(render 180 178 1 1 22 0 0 1 1 0 0 0 symlink health)"
T_ATTN=()
eq "warning + drift lists both bullets under the verdict" "
Summary
  ✔ ok           178 / 180
  ✖ drift          1
  ⚠ warnings       1
  ✋ by hand      22   (scripts/manual-steps.sh list)
  → run ./macconfig-check.sh --fix to repair 1 safe item(s)
  2 need attention (1 drift, 1 warning)
    - drift  Symlinks: ~/.gitconfig -> elsewhere (expected repo) (fix: symlink)
    - warn   Mac health: disk: only 12 GB free (8%) on Data (Needs Paul)" "$attn_out"
eq "warning + drift is two bullets" "2" "$(printf '%s\n' "$attn_out" | grep -c '^    - ' || true)"

# Clean run: nothing extra, even if a stray item was left in the array.
T_ATTN=("warn${US}Mac health${US}health${US}should not appear")
clean_out="$(render 139 139 0 0 20 0 0 0 0 0 0 0)"
T_ATTN=()
eq "clean output unchanged" "
Summary
  ✔ ok           139 / 139
  ✖ drift          0
  ⚠ warnings       0
  ✋ by hand      20   (scripts/manual-steps.sh list)
  All good" "$clean_out"
eq "clean has no attention bullet" "" "$(printf '%s\n' "$clean_out" | grep -F 'should not appear' || true)"

# --no-color / a pipe: C_* empty, so the bullets are plain text.
eq "--no-color plain (no ANSI)" "0" "$(printf '%s' "$attn_out" | grep -c $'\033' || true)"
T_COLOR=1
T_ATTN=("$DRIFT_ITEM" "$WARN_ITEM")
color_out="$(render 180 178 1 1 22 0 0 1 1 0 0 0 symlink health)"
T_COLOR=0
T_ATTN=()
eq "drift bullet is red" "1" "$(printf '%s\n' "$color_out" | grep -F -c $'\033[31m- drift' || true)"
eq "warn bullet is yellow" "1" "$(printf '%s\n' "$color_out" | grep -F -c $'\033[33m- warn' || true)"
eq "each bullet resets colour" "2" "$(printf '%s\n' "$color_out" | grep '^    '$'\033' | grep -c $'\033\[0m$' || true)"

# Long reasons are cut; the hint stays on the line. Budget leaves 62 characters of
# message for this section + "Needs Paul" (see attn_format).
LONG_MSG="disk: only 12 GB free (8%) on Data - want >= 50 GB and >= 15% PLUS-A-LONG-TAIL-THAT-MUST-BE-CUT"
T_ATTN=("warn${US}Mac health${US}health${US}$LONG_MSG")
long_out="$(render 180 179 0 1 22 0 0 0 1 0 0 0 health)"
T_ATTN=()
long_line="$(printf '%s\n' "$long_out" | grep '^    - warn')"
eq "long bullet keeps the hint" "1" "$(printf '%s' "$long_line" | grep -c '(Needs Paul)$' || true)"
eq "long bullet is truncated" "1" "$(printf '%s' "$long_line" | grep -c '\.\.\.' || true)"
eq "long bullet drops the tail" "0" "$(printf '%s' "$long_line" | grep -c 'PLUS-A-LONG-TAIL' || true)"
if [ "${#long_line}" -le 100 ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL: long bullet width\n  length: %s\n  line: [%s]\n' "${#long_line}" "$long_line"; fi

# Parenthetical section titles shorten to the name. manual-step says how to fix.
T_ATTN=("warn${US}Manual steps (lib/manual-steps.list)${US}manual-step${US}39. Raycast hotkey clashes")
manual_out="$(render 180 179 0 1 22 0 0 0 1 0 0 0 manual-step)"
T_ATTN=()
eq "manual step bullet" "    - warn   Manual steps: 39. Raycast hotkey clashes (manual step)" \
  "$(printf '%s\n' "$manual_out" | grep '^    - ')"

# --fix: bullets are what's still outstanding after the re-check, not what was fixed.
T_RECHECK_RAN=1
T_ATTN=("$DRIFT_ITEM" "$WARN_ITEM")
T_RECHECK=("$WARN_ITEM")
fix_out="$(render 180 179 1 1 22 1 0 0 1 1 1 0 symlink health)"
T_RECHECK_RAN=0
T_ATTN=()
T_RECHECK=()
eq "--fix lists the warning still outstanding" "
Summary
  ✔ ok           179 / 180
  ✖ drift          0   (was 1 before --fix)
  ⚠ warnings       1
  ✋ by hand      22   (scripts/manual-steps.sh list)
  ↻ fixed          1
  ☞ needs Paul     1
  1 needs attention (1 warning)
    - warn   Mac health: disk: only 12 GB free (8%) on Data (Needs Paul)" "$fix_out"
eq "--fix bullet omits the repaired drift" "" "$(printf '%s\n' "$fix_out" | grep -F 'Symlinks' || true)"

printf 'check-summary tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
