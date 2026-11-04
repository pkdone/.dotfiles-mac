#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2317  # rollup vars and stubs are used after eval / source
#
# Manual steps that macconfig already reported stay in their numbered place.
# The line uses that section's ok / warn / fail when the section recorded one,
# and info otherwise. It is not counted again, and it does not say to press s.
# Run: ./tests/manual-covered-lines.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hermetic.sh disable=SC1091
. "$DIR/tests/hermetic.sh"
MS="$DIR/scripts/manual-steps.sh"
LIST="$DIR/lib/manual-steps.list"
CHECK="$DIR/macconfig-check.sh"

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
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;;
    *) pass=$((pass + 1)) ;; esac
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"
cat > "$tmp/bin/open" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$tmp/bin/open"
cat > "$tmp/ms" <<'EOF'
#!/bin/sh
printf '%s\n' "$PORCELAIN"
EOF
chmod +x "$tmp/ms"
SAFE="$(hermetic_safe_root)"
export DOTDIR="$DIR"
export PATH="$tmp/bin:$SAFE"
export NO_COLOR=1
# shellcheck source=../lib/covered-steps.sh disable=SC1091
. "$DIR/lib/covered-steps.sh"

# ---- section rollup: worst of pass / warn / bad, and nothing for a skip ----
BLOCK="$(awk '/^# ---- section rollup ---$/ {on = 1} /^# ---- end section rollup ---$/ {on = 0} on' "$CHECK")"
has "section rollup is in macconfig-check.sh" "section_record()" "$BLOCK"
rollup="$(
  set -euo pipefail
  US=$'\037'
  eval "$BLOCK"
  SECTION=""
  section_record ok
  if section_status_of "Desktop widgets" >/dev/null 2>&1; then
    echo "empty heading was recorded"
    exit 1
  fi
  SECTION="Desktop widgets"
  section_record ok
  [ "$(section_status_of "Desktop widgets")" = ok ] || { echo "pass did not record ok"; exit 1; }
  section_record warn
  [ "$(section_status_of "Desktop widgets")" = warn ] || { echo "warn did not replace ok"; exit 1; }
  section_record ok
  [ "$(section_status_of "Desktop widgets")" = warn ] || { echo "a later ok downgraded warn"; exit 1; }
  SECTION="Allow in the Menu Bar"
  section_record fail
  [ "$(section_status_of "Allow in the Menu Bar")" = fail ] || { echo "fail was not recorded"; exit 1; }
  [ "$(section_status_of "Desktop widgets")" = warn ] || { echo "a second heading changed the first"; exit 1; }
  if section_status_of "Nope" >/dev/null 2>&1; then
    echo "unknown heading claimed a status"
    exit 1
  fi
  echo ok
)"
eq "section rollup keeps the worst result and does not invent one" "ok" "$rollup"
has "pass records ok" "section_record ok" "$(grep '^pass()' "$CHECK")"
has "warn records warn" "section_record warn" "$(grep '^warn()' "$CHECK")"
has "bad records fail" "section_record fail" "$(grep '^bad()' "$CHECK")"
miss "info does not record a section result" "section_record" "$(grep '^info()' "$CHECK")"
miss "note does not record a section result" "section_record" "$(grep '^note()' "$CHECK")"
miss "skip does not record a section result" "section_record" "$(grep '^skip()' "$CHECK")"

# ---- headings match the hdr strings the main check prints ----
eq "menubar heading" "Allow in the Menu Bar" "$(covered_section_heading menubar-third-party-hide)"
eq "unknown id has no heading" "" "$(covered_section_heading no-such-step || true)"

awk -F'|' '$0 ~ /^[[:space:]]*(#|$)/ { next } NF < 6 { next } { print }' "$LIST" > "$tmp/rows"
ids=()
titles=()
checks=()
while IFS='|' read -r id group title where target check; do
  : "$group" "$where" "$target"
  ids+=("$id")
  titles+=("$title")
  checks+=("$check")
done < "$tmp/rows"
rows="$(grep -cEv '^[[:space:]]*(#|$)' "$LIST")"
eq "parsed row count matches the list" "$rows" "${#ids[@]}"

i=0
while [ "$i" -lt "${#ids[@]}" ]; do
  id="${ids[$i]}"
  check="${checks[$i]}"
  case "$check" in
    @macconfig:*|remove-widgets)
      heading="$(covered_section_heading "$id" || true)"
      eq "$id has a section heading" "nonempty" "${heading:+nonempty}"
      found="$(grep -F "hdr \"$heading\"" "$DIR"/checks/*.sh || true)"
      has "$id heading is printed by a section" "hdr \"$heading\"" "$found"
      ;;
  esac
  i=$((i + 1))
done

# ---- the Manual steps section prints the pointer and does not count it ----
run_manual() { # porcelain widgets-flag status-mode
  (
    set -euo pipefail
    export PORCELAIN="$1" WIDGETS_SECTION_RAN="${2:-}" DOTDIR="$DIR" NO_COLOR=1
    export PATH="$tmp/bin:$SAFE" HOME="$tmp/home" MANUAL_STEPS_BIN="$tmp/ms"
    CHECKED=0
    OKS=0
    DRIFT=0
    WARN=0
    HAND=0
    hdr() { :; }
    fixid() { :; }
    pass() { OKS=$((OKS + 1)); printf 'PASS %s\n' "$1"; }
    warn() { WARN=$((WARN + 1)); printf 'WARN %s\n' "$1"; }
    bad() { DRIFT=$((DRIFT + 1)); printf 'DRIFT %s\n' "$1"; }
    info() { HAND=$((HAND + 1)); printf 'INFO %s\n' "$1"; }
    note() { printf 'NOTE %s\n' "$1"; }
    case "${3:-map}" in
      none) ;;
      missing) section_status_of() { return 1; } ;;
      ok) section_status_of() { printf '%s' ok; } ;;
      *)
        section_status_of() {
          case "$1" in
            "MDM / company apps") printf '%s' ok ;;
            "Login Items") printf '%s' warn ;;
            "Allow in the Menu Bar") printf '%s' fail ;;
            "Desktop widgets") printf '%s' ok ;;
            *) return 1 ;;
          esac
        }
        ;;
    esac
    # shellcheck source=../checks/manual.sh disable=SC1091
    . "$DIR/checks/manual.sh"
    printf 'COUNTS %s %s %s %s %s\n' "$CHECKED" "$OKS" "$DRIFT" "$WARN" "$HAND"
  )
}

nums_of() {
  printf '%s\n' "$1" | sed -nE 's/^(  (ok|warn|fail|info) +|(PASS|WARN|INFO|DRIFT|NOTE) )([0-9]+)\..*/\4/p' | tr '\n' ' ' | sed 's/ $//'
}

small="$(printf '%s\n' \
  'covered|1|mdm-apps|Install the company apps|' \
  'hand|2|charge-limit|Charge Limit 80%|' \
  'covered|6|tailscale-login|Add Tailscale to Open at Login|' \
  'ok|7|cursor-nightly|Install Cursor Nightly|installed' \
  'ok|30|remove-widgets|Remove every widget|none placed' \
  'covered|50|menubar-third-party-hide|Allow in the Menu Bar|' \
  'covered|99|not-a-mapped-step|Mystery step|')"

out="$(run_manual "$small" 1 map)"
eq "small fixture order" "1 2 6 7 30 50 99" "$(nums_of "$out")"
has "company apps uses the section ok" \
  "  ok    1. Install the company apps — checked above under MDM / company apps" "$out"
has "tailscale uses the section warn" \
  "  warn  6. Add Tailscale to Open at Login — checked above under Login Items" "$out"
has "menu bar uses the section fail" \
  "  fail  50. Allow in the Menu Bar — checked above under Allow in the Menu Bar" "$out"
has "placed widgets use the Desktop widgets ok" \
  "  ok    30. Remove every widget — checked above under Desktop widgets" "$out"
has "an unmapped covered step stays neutral" \
  "  info  99. Mystery step — checked above" "$out"
miss "an unmapped step does not name a section" "Mystery step — checked above under" "$out"
has "a real ok is still printed" "PASS 7. Install Cursor Nightly — installed" "$out"
miss "a pointer is not a second pass" "PASS 1. Install the company apps" "$out"
miss "a fail pointer is not a second drift" "DRIFT" "$out"
miss "a warn pointer is not a second warning" "WARN " "$out"
pointers="$(printf '%s\n' "$out" | grep 'checked above' || true)"
miss "pointer lines do not say to press s" "press s" "$pointers"
has "a by-hand step still says to press s" "press s" "$(printf '%s\n' "$out" | grep 'Charge Limit' || true)"
eq "pointers are not in the summary counts" "COUNTS 1 1 0 0 1" \
  "$(printf '%s\n' "$out" | grep '^COUNTS ')"

out="$(run_manual "$small" 1 missing)"
has "a known section with no recorded result is info" \
  "  info  1. Install the company apps — checked above under MDM / company apps" "$out"
miss "a missing result is not called ok" "  ok    " "$out"
eq "a missing result is still not counted" "COUNTS 1 1 0 0 1" \
  "$(printf '%s\n' "$out" | grep '^COUNTS ')"

out="$(run_manual "$small" 1 none)"
has "no rollup function is info, not ok" \
  "  info  1. Install the company apps — checked above under MDM / company apps" "$out"
miss "no rollup data is not called ok" "  ok    " "$out"

out="$(run_manual "$small" "" map)"
has "widgets are reported here when that section did not run" \
  "PASS 30. Remove every widget — none placed" "$out"
miss "widgets are not a pointer when that section did not run" \
  "checked above under Desktop widgets" "$out"
eq "a widgets result counts when the section did not run" "COUNTS 2 2 0 0 1" \
  "$(printf '%s\n' "$out" | grep '^COUNTS ')"

# Every real step, in list order. @macconfig rows and remove-widgets are pointers.
full=""
i=0
hands=0
while [ "$i" -lt "${#ids[@]}" ]; do
  num=$((i + 1))
  id="${ids[$i]}"
  title="${titles[$i]}"
  check="${checks[$i]}"
  case "$check" in
    @macconfig:*) full="${full}covered|${num}|${id}|${title}|"$'\n' ;;
    remove-widgets) full="${full}ok|${num}|${id}|${title}|none"$'\n' ;;
    *) full="${full}hand|${num}|${id}|${title}|"$'\n'; hands=$((hands + 1)) ;;
  esac
  i=$((i + 1))
done
out="$(run_manual "$full" 1 ok)"
eq "full list numbers have no gaps" "$(seq 1 "$rows" | tr '\n' ' ' | sed 's/ $//')" "$(nums_of "$out")"
eq "full list counts only the steps not already reported" "COUNTS 0 0 0 0 $hands" \
  "$(printf '%s\n' "$out" | grep '^COUNTS ')"
i=0
covered_n=0
while [ "$i" -lt "${#ids[@]}" ]; do
  num=$((i + 1))
  id="${ids[$i]}"
  title="${titles[$i]}"
  check="${checks[$i]}"
  case "$check" in
    @macconfig:*|remove-widgets)
      covered_n=$((covered_n + 1))
      heading="$(covered_section_heading "$id")"
      has "$id keeps number $num" \
        "  ok    ${num}. ${title} — checked above under ${heading}" "$out"
      ;;
  esac
  i=$((i + 1))
done
eq "one pointer per covered step" "$covered_n" "$(printf '%s\n' "$out" | grep -c 'checked above' || true)"
full_pointers="$(printf '%s\n' "$out" | grep 'checked above' || true)"
miss "full-list pointers do not say to press s" "press s" "$full_pointers"

# Owning the section still skips the walk-through. It does not ask to press s.
printf '%s\n' 'mdm-apps|Company apps (MDM)|Install the company apps|Where|app:Fleet Desktop|@macconfig:mdm' > "$tmp/one.list"
open_out="$(printf 's\n' | HOME="$tmp/home" MACCONFIG_OWNS_SECTIONS=1 MANUAL_STEPS_OPEN_TTY=1 \
  MANUAL_STEPS_LIST="$tmp/one.list" PATH="$tmp/bin:$SAFE" "$MS" open 2>"$tmp/open.err" || true)"
miss "open does not show a step the section owns" "Install the company apps" "$open_out"
miss "open does not say to press s for a step the section owns" "press s" "$open_out"
has "open has nothing to walk when the only step is owned" "Nothing to do:" "$open_out"
pending_out="$(HOME="$tmp/home" MACCONFIG_OWNS_SECTIONS=1 MANUAL_STEPS_LIST="$tmp/one.list" \
  PATH="$tmp/bin:$SAFE" "$MS" pending 2>"$tmp/pending.err" || true)"
miss "pending does not show a step the section owns" "Install the company apps" "$pending_out"
miss "pending does not say to press s for a step the section owns" "press s" "$pending_out"
has "pending counts the owned step as already done" "Skipped 1 already done." "$pending_out"

printf 'manual-covered-lines tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
