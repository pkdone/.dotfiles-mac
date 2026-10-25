#!/usr/bin/env bash
#
# Group headings in scripts/manual-steps.sh check and open.
# check's human output uses the same headings as list. --porcelain does not:
# macconfig-check.sh reads status|num|id|title|detail and must not see headings.
# open prints a heading only for a group that still has a step to show.
# MANUAL_STEPS_OPEN_TTY=1 is the test hook for the stdin-is-a-terminal guard
# (same idea as MANUAL_STEPS_LIST and the other MANUAL_STEPS_* overrides).
# Run: ./tests/manual-steps-headings.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MS="$DIR/../scripts/manual-steps.sh"
export NO_COLOR=1

pass=0
fail=0
eq() {  # description expected actual
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"
  fi
}
has() {  # description needle haystack
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n' "$1" "$2" ;; esac
}
miss() {  # description needle haystack
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n' "$1" "$2" ;;
    *) pass=$((pass + 1)) ;; esac
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/open" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${OPEN_LOG:?}"
exit 0
EOF
chmod +x "$tmp/bin/open"
export OPEN_LOG="$tmp/open.log"
: > "$OPEN_LOG"

# Pass is entirely ok. Mixed starts with an ok step, then a warn. Todo is by
# hand. Covered is verified elsewhere. Groups stay together, as the parser requires.
cat > "$tmp/steps.list" <<'EOF'
ok-pass|Pass|Present app|On disk|app:Finder|app:/etc/passwd
ok-mixed|Mixed|Present in mixed|On disk||app:/etc/passwd
bad-mixed|Mixed|Missing app|On disk|app:NoSuch|app:/no/such/manual-steps-app
hand-a|Todo|Do the first thing|System Settings pane|x-apple.systempreferences:com.apple.Trackpad-Settings.extension|
hand-b|Todo|Do the second thing|Nowhere in particular||
cov|Covered|Already covered elsewhere|Own section||@macconfig-check.sh
EOF

# Same padding check prints: two spaces, a 19-wide label, a space, a 2-wide number.
status_line() { printf '  %-19s %2d. %s\n' "$1" "$2" "$3"; }
group_names() { printf '%s\n' "$1" | grep -xE 'Pass|Mixed|Todo|Covered' || true; }

# A heading is a blank line plus the group name, and the status lines under it
# stay indented. A blank line ends the group, so the summary is not included.
headings_indent_ok() {
  printf '%s\n' "$1" | awk '
    $0 == "Pass" || $0 == "Mixed" || $0 == "Todo" || $0 == "Covered" {
      if (prev != "") bad = 1
      in_group = 1
      prev = $0
      next
    }
    in_group && $0 == "" { in_group = 0; prev = $0; next }
    in_group && substr($0, 1, 2) != "  " { bad = 1 }
    { prev = $0 }
    END { exit bad ? 1 : 0 }
  '
}

{
  printf '%s\n' "Manual steps — read-only checks"
  printf '\n%s\n' "Pass"
  status_line "ok" 1 "Present app — installed"
  printf '\n%s\n' "Mixed"
  status_line "ok" 2 "Present in mixed — installed"
  status_line "warn" 3 "Missing app — not found at /no/such/manual-steps-app"
  printf '\n%s\n' "Todo"
  status_line "by hand" 4 "Do the first thing"
  status_line "by hand" 5 "Do the second thing"
  printf '\n%s\n' "Covered"
  status_line "macconfig-check.sh" 6 "Already covered elsewhere — verified by macconfig-check.sh"
  printf '\n%s\n' "Summary: 2 ok, 1 warn, 2 to check by hand, 1 verified by macconfig-check.sh."
} > "$tmp/expect-check.txt"

cat > "$tmp/expect-porcelain.txt" <<'EOF'
ok|1|ok-pass|Present app|installed
ok|2|ok-mixed|Present in mixed|installed
warn|3|bad-mixed|Missing app|not found at /no/such/manual-steps-app
hand|4|hand-a|Do the first thing|
hand|5|hand-b|Do the second thing|
covered|6|cov|Already covered elsewhere|verified by macconfig-check.sh
EOF

# Prompt text is unchanged. A later group heading adds the blank line after
# the prompt, which itself does not end with a newline.
key_prompt() { printf '      [Enter] open%s, s skip, q quit: ' "$1"; }
{
  printf '%s\n' "Walking through the manual steps. Enter = done/next, s = skip, q = quit."
  printf '\n%s\n' "Mixed"
  printf '%s\n' "3. Missing app" \
    "      Not set yet: not found at /no/such/manual-steps-app" \
    "      On disk"
  key_prompt ""
  printf '\n\n%s\n' "Todo"
  printf '%s\n' "4. Do the first thing" \
    "      Can't check this automatically. If it's already set, press s." \
    "      System Settings pane"
  key_prompt ""
  printf '\n%s\n' "5. Do the second thing"
  printf '%s\n' \
    "      Can't check this automatically. If it's already set, press s." \
    "      Nowhere in particular"
  key_prompt " (nothing to open)"
  printf '\n%s\n' "Done. Run scripts/manual-steps.sh check (or ./macconfig-check.sh) to confirm."
} > "$tmp/expect-open.txt"

{
  printf '%s\n' "Walking through the manual steps. Enter = done/next, s = skip, q = quit."
  printf '\n%s\n' "Pass"
  printf '%s\n' "1. Present app" \
    "      Already done, shown because of --all" \
    "      On disk"
  key_prompt ""
  printf '\n\n%s\n' "Mixed"
  printf '%s\n' "2. Present in mixed" \
    "      Already done, shown because of --all" \
    "      On disk"
  key_prompt " (nothing to open)"
  printf '\n%s\n' "3. Missing app"
  printf '%s\n' \
    "      Not set yet: not found at /no/such/manual-steps-app" \
    "      On disk"
  key_prompt ""
  printf '\n\n%s\n' "Todo"
  printf '%s\n' "4. Do the first thing" \
    "      Can't check this automatically. If it's already set, press s." \
    "      System Settings pane"
  key_prompt ""
  printf '\n%s\n' "5. Do the second thing"
  printf '%s\n' \
    "      Can't check this automatically. If it's already set, press s." \
    "      Nowhere in particular"
  key_prompt " (nothing to open)"
  printf '\n\n%s\n' "Covered"
  printf '%s\n' "6. Already covered elsewhere" \
    "      Already done, shown because of --all" \
    "      Own section"
  key_prompt " (nothing to open)"
  printf '\n%s\n' "Done. Run scripts/manual-steps.sh check (or ./macconfig-check.sh) to confirm."
} > "$tmp/expect-all.txt"

{
  printf '%s\n' "Walking through the manual steps. Enter = done/next, s = skip, q = quit."
  printf '\n%s\n' "Mixed"
  printf '%s\n' "3. Missing app" \
    "      Not set yet: not found at /no/such/manual-steps-app" \
    "      On disk"
  key_prompt ""
  printf '      Press Enter when done: '
  printf '\n\n%s\n' "Todo"
  printf '%s\n' "4. Do the first thing" \
    "      Can't check this automatically. If it's already set, press s." \
    "      System Settings pane"
  key_prompt ""
  printf '%s\n' "Stopped at step 4."
} > "$tmp/expect-enter.txt"

# ---- check: headings in human output, none in porcelain ------------------
check_out="$(MANUAL_STEPS_LIST="$tmp/steps.list" "$MS" check 2>"$tmp/check.err")"
check_rc=$?
eq "check exits 1 when a step warns" 1 "$check_rc"
eq "check stderr stays empty" "" "$(cat "$tmp/check.err")"
eq "check human output has group headings and an unchanged summary" \
  "$(cat "$tmp/expect-check.txt")" "$check_out"
eq "check headings match list headings" \
  "$(group_names "$(MANUAL_STEPS_LIST="$tmp/steps.list" "$MS" list)")" \
  "$(group_names "$check_out")"
if headings_indent_ok "$check_out"; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL: %s\n' "check status lines stay indented under the heading"
fi
eq "summary line is unchanged" \
  "Summary: 2 ok, 1 warn, 2 to check by hand, 1 verified by macconfig-check.sh." \
  "$(printf '%s\n' "$check_out" | tail -n 1)"

porc_out="$(MANUAL_STEPS_LIST="$tmp/steps.list" "$MS" check --porcelain 2>"$tmp/porc.err")"
porc_rc=$?
eq "porcelain still exits 1 when a step warns" 1 "$porc_rc"
eq "porcelain stderr stays empty" "" "$(cat "$tmp/porc.err")"
eq "porcelain output is unchanged" "$(cat "$tmp/expect-porcelain.txt")" "$porc_out"
eq "porcelain has no group headings" "" "$(group_names "$porc_out")"
miss "porcelain has no human header" "Manual steps" "$porc_out"
miss "porcelain has no summary" "Summary:" "$porc_out"
plain_porc="$(printf '%s\n' "$porc_out" | grep -v '|' || true)"
eq "porcelain lines are all status records" "" "$plain_porc"

# ---- open: headings only for groups that still have a step ---------------
open_out="$(printf 's\ns\ns\n' | MANUAL_STEPS_OPEN_TTY=1 MANUAL_STEPS_LIST="$tmp/steps.list" \
  PATH="$tmp/bin:$PATH" "$MS" open 2>"$tmp/open.err")"
open_rc=$?
eq "open exits 0" 0 "$open_rc"
eq "open stderr stays empty" "" "$(cat "$tmp/open.err")"
eq "open prints headings only for groups with a step left" \
  "$(cat "$tmp/expect-open.txt")" "$open_out"
eq "open heading order skips empty groups" "$(printf '%s\n' "Mixed" "Todo")" "$(group_names "$open_out")"
eq "a shown group is headed once" 1 "$(printf '%s\n' "$open_out" | grep -cx 'Mixed' || true)"
miss "open hides a group whose steps already pass" "Pass" "$open_out"
miss "open hides a covered group" "Covered" "$open_out"
miss "open hides a step that already passes" "Present in mixed" "$open_out"
miss "open hides a covered step" "Already covered elsewhere" "$open_out"
has "open still shows the step that warns" "3. Missing app" "$open_out"
eq "skip does not launch open" "" "$(cat "$OPEN_LOG")"

all_out="$(printf 's\ns\ns\ns\ns\ns\n' | MANUAL_STEPS_OPEN_TTY=1 MANUAL_STEPS_LIST="$tmp/steps.list" \
  PATH="$tmp/bin:$PATH" "$MS" open --all 2>"$tmp/all.err")"
all_rc=$?
eq "open --all exits 0" 0 "$all_rc"
eq "open --all stderr stays empty" "" "$(cat "$tmp/all.err")"
eq "open --all heads every group" "$(cat "$tmp/expect-all.txt")" "$all_out"
eq "open --all heading order" "$(printf '%s\n' "Pass" "Mixed" "Todo" "Covered")" "$(group_names "$all_out")"
has "open --all shows a step that already passes" "1. Present app" "$all_out"
has "open --all shows a covered step" "6. Already covered elsewhere" "$all_out"

: > "$OPEN_LOG"
enter_out="$(printf '\n\nq\n' | MANUAL_STEPS_OPEN_TTY=1 MANUAL_STEPS_LIST="$tmp/steps.list" \
  PATH="$tmp/bin:$PATH" "$MS" open 2>"$tmp/enter.err")"
enter_rc=$?
eq "open Enter then quit exits 0" 0 "$enter_rc"
eq "open Enter then quit stderr stays empty" "" "$(cat "$tmp/enter.err")"
eq "Enter, the done prompt, and quit stay the same" "$(cat "$tmp/expect-enter.txt")" "$enter_out"
eq "Enter launches the step target" "-a NoSuch" "$(cat "$OPEN_LOG")"

# A list whose every step already passes: no heading, and the nothing-to-do line.
cat > "$tmp/onlyok.list" <<'EOF'
ok-pass|Pass|Present app|On disk||app:/etc/passwd
cov|Covered|Already covered elsewhere|Own section||@macconfig-check.sh
EOF
none_out="$(printf 's\n' | MANUAL_STEPS_OPEN_TTY=1 MANUAL_STEPS_LIST="$tmp/onlyok.list" \
  PATH="$tmp/bin:$PATH" "$MS" open 2>"$tmp/none.err")"
none_rc=$?
eq "open with nothing left exits 0" 0 "$none_rc"
eq "open with nothing left has no headings" "" "$(group_names "$none_out")"
eq "open with nothing left says so" \
  "Walking through the manual steps. Enter = done/next, s = skip, q = quit.
Nothing to do: every checkable step already passes (use --all to see them all).

Done. Run scripts/manual-steps.sh check (or ./macconfig-check.sh) to confirm." \
  "$none_out"

# Without the hook, a pipe is not a terminal and the walk-through does not run.
notty_out="$(printf 's\n' | MANUAL_STEPS_LIST="$tmp/steps.list" PATH="$tmp/bin:$PATH" \
  "$MS" open 2>"$tmp/notty.err")"
notty_rc=$?
eq "no tty exits 0" 0 "$notty_rc"
eq "no tty stderr stays empty" "" "$(cat "$tmp/notty.err")"
eq "no tty skips the walk-through" \
  "manual-steps.sh open: stdin isn't a terminal — skipping the walk-through (run it from a terminal)." \
  "$notty_out"
miss "no tty does not print a heading" "Mixed" "$notty_out"

printf 'manual-steps headings tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
