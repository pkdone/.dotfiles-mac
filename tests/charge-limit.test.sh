#!/usr/bin/env bash
#
# Charge Limit 80% is a manual step. Apple documents no command that sets it,
# and the chosen percentage cannot be read without a private entitlement, so
# the check stays empty. A missing key must not become a warning.
# Run: ./tests/charge-limit.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="$DIR/lib/manual-steps.list"
DOC="$DIR/docs/manual-steps.md"

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
miss() {  # description needle haystack
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n' "$1" "$2" ;;
    *) pass=$((pass + 1)) ;; esac
}

row="$(awk -F'|' '$1 == "charge-limit" { print; exit }' "$LIST")"
eq "charge-limit row exists" 1 "$(printf '%s\n' "$row" | grep -c .)"
eq "charge-limit group" "Display, keyboard & desktop" "$(printf '%s\n' "$row" | cut -d'|' -f2)"
eq "charge-limit title" \
  "Charge Limit 80% (Apple silicon laptops). Check by hand: the chosen percentage cannot be read" \
  "$(printf '%s\n' "$row" | cut -d'|' -f3)"
eq "charge-limit where" \
  "System Settings → Battery → click ⓘ next to Charging → drag Charge Limit to 80% (leave Optimised Battery Charging on) → Done" \
  "$(printf '%s\n' "$row" | cut -d'|' -f4)"
eq "charge-limit opens Battery settings" \
  "x-apple.systempreferences:com.apple.Battery-Settings.extension" \
  "$(printf '%s\n' "$row" | cut -d'|' -f5)"
eq "charge-limit check is empty" "" "$(printf '%s\n' "$row" | cut -d'|' -f6)"

prev="$(awk -F'|' '
  $1 ~ /^#/ || $1 ~ /^[[:space:]]*$/ { next }
  $1 == "charge-limit" { print prev; exit }
  { prev = $1 }
' "$LIST")"
eq "charge-limit follows ac-sleep" "ac-sleep" "$prev"

doc="$(cat "$DOC")"
# shellcheck disable=SC2016  # needles are markdown, compared literally
has "manual-steps doc names the step" 'manual step `charge-limit`' "$doc"
has "manual-steps doc says 80%" "is 80% on an Apple silicon laptop" "$doc"
# shellcheck disable=SC2016
has "manual-steps doc says there is no pmset setter" '`pmset` has none' "$doc"
has "manual-steps doc names pmset -g battlimit" "pmset -g battlimit" "$doc"
has "manual-steps doc names the private entitlement" "com.apple.private.iokit.soc-limit" "$doc"
has "manual-steps doc names ioreg" "ioreg -rn AppleSmartBattery" "$doc"
has "manual-steps doc names system_profiler" "system_profiler SPPowerDataType" "$doc"
has "manual-steps doc says a desktop has no battery" "A desktop has no battery." "$doc"
has "manual-steps doc leaves the step by hand" "The step stays by hand." "$doc"
has "table row is by hand" \
  "| Charge Limit 80% (Apple silicon laptops). Check by hand: the chosen percentage cannot be read | System Settings → Battery → click ⓘ next to Charging → drag Charge Limit to 80% (leave Optimised Battery Charging on) → Done | by hand |" \
  "$doc"

# No check, so no fixid. A real read would add both together.
checks="$(cat "$DIR"/checks/*.sh)"
miss "no charge-limit fixid" "fixid charge-limit" "$checks"
eq "autofix has no charge-limit row" "" \
  "$(awk -F'|' '$1 == "charge-limit" { print; exit }' "$DIR/lib/autofix.list")"
miss "macos.sh does not set a charge limit" "charge-limit" "$(cat "$DIR/macos.sh")"

printf 'charge-limit tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
