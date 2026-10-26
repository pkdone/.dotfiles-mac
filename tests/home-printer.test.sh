#!/usr/bin/env bash
#
# Home printer step. A fake lpstat only — nothing adds a queue.
# Run: ./tests/home-printer.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hermetic.sh disable=SC1091
. "$DIR/tests/hermetic.sh"
MS="$DIR/scripts/manual-steps.sh"
LIST="$DIR/lib/manual-steps.list"

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

row="$(awk -F'|' '$1=="home-printer" { print; exit }' "$LIST")"
eq "printer step title" "Add the home printer HP ENVY 6000 series" \
  "$(printf '%s\n' "$row" | cut -d'|' -f3)"
eq "printer step group" Printer "$(printf '%s\n' "$row" | cut -d'|' -f2)"
eq "printer step opens Printers and Scanners" \
  "x-apple.systempreferences:com.apple.Print-Scan-Settings.extension" \
  "$(printf '%s\n' "$row" | cut -d'|' -f5)"
has "printer step names Add Printer" "Add Printer, Scanner or Fax" "$row"
has "printer step names the Default tab" "Default tab" "$row"
eq "printer step check is the named check" home-printer \
  "$(printf '%s\n' "$row" | cut -d'|' -f6)"
miss "the check never adds a printer" lpadmin "$(cat "$DIR/scripts/manual-steps.sh")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"
mkdir -p "$bin"
cat > "$bin/open" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$bin/lpstat" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${LPSTAT_LOG:?}"
case "${1:-}" in
  -p) printf '%s\n' "${LPSTAT_P-}" ;;
  -v) printf '%s\n' "${LPSTAT_V-}" ;;
  *) exit 1 ;;
esac
exit "${LPSTAT_RC:-0}"
EOF
chmod +x "$bin/open" "$bin/lpstat"
# $bin first, then ordinary Unix tools only. $PATH is not copied: on a Mac
# that would still find /usr/bin/lpstat after the stub is removed.
SAFE="$(hermetic_safe_root)"
printf '%s\n' \
  'home-printer|Printer|Add the home printer HP ENVY 6000 series|System Settings → Printers & Scanners|x-apple.systempreferences:com.apple.Print-Scan-Settings.extension|home-printer' \
  > "$tmp/steps.list"
export NO_COLOR=1 LPSTAT_LOG="$tmp/lpstat.log"
: > "$LPSTAT_LOG"

check() {
  LPSTAT_P="${1-}" LPSTAT_V="${2-}" LPSTAT_RC="${3:-0}" \
    PATH="$bin:$SAFE" MANUAL_STEPS_LIST="$tmp/steps.list" \
    "$MS" check --porcelain
}

out="$(check 'printer HP_ENVY_6000_series_ABCD is idle. enabled since today')"
eq "an underscored queue is ok" ok "$(printf '%s\n' "$out" | cut -d'|' -f1)"
has "an underscored queue is named" "HP ENVY 6000 series is in the printer list" "$out"
eq "a listed queue does not need lpstat -v" "" "$(grep -- '-v' "$LPSTAT_LOG" || true)"

: > "$LPSTAT_LOG"
out="$(check 'printer HP ENVY 6000 series is idle. enabled since today')"
eq "a spaced queue name is ok" ok "$(printf '%s\n' "$out" | cut -d'|' -f1)"

: > "$LPSTAT_LOG"
out="$(check 'printer HP_LaserJet is idle. enabled since today')"
eq "another printer is not set yet" warn "$(printf '%s\n' "$out" | cut -d'|' -f1)"
has "another printer mentions the home network" "home network" "$out"
miss "another printer is not described as already listed" "is in the printer list" "$out"

: > "$LPSTAT_LOG"
out="$(check '' 'device for HP_ENVY_6000_series: dnssd://HP%20ENVY%206000')"
eq "lpstat -v names the queue when -p does not" ok "$(printf '%s\n' "$out" | cut -d'|' -f1)"
has "the fallback calls lpstat -v" "-v" "$(cat "$LPSTAT_LOG")"

: > "$LPSTAT_LOG"
out="$(check '' '')"
eq "no queues is not set yet" warn "$(printf '%s\n' "$out" | cut -d'|' -f1)"
has "no queues says it can only be added at home" "only be added on the home network" "$out"

rm -f "$bin/lpstat"
# A decoy earlier on an inherited PATH would count as the printer. The
# closed path must not see it, and must not see /usr/bin/lpstat either.
decoy="$tmp/decoy"
mkdir -p "$decoy"
cat > "$decoy/lpstat" <<'EOF'
#!/bin/sh
printf '%s\n' "printer HP_ENVY_6000_series is idle. enabled since today"
exit 0
EOF
chmod +x "$decoy/lpstat"
leak="$(PATH="$decoy:$SAFE" MANUAL_STEPS_LIST="$tmp/steps.list" "$MS" check --porcelain)"
eq "a planted lpstat counts as the printer" ok "$(printf '%s\n' "$leak" | cut -d'|' -f1)"
found="$(PATH="$bin:$SAFE" command -v lpstat || true)"
eq "the closed path has no lpstat" "" "$found"
out="$(PATH="$bin:$SAFE" MANUAL_STEPS_LIST="$tmp/steps.list" "$MS" check --porcelain)"
eq "a missing lpstat is not set yet" warn "$(printf '%s\n' "$out" | cut -d'|' -f1)"

cat > "$bin/lpstat" <<'EOF'
#!/bin/sh
case "${1:-}" in
  -p) printf '%s\n' "${LPSTAT_P-}" ;;
  -v) printf '%s\n' "${LPSTAT_V-}" ;;
esac
exit 0
EOF
chmod +x "$bin/lpstat"
open_out="$(printf 's\n' | LPSTAT_P='printer Other is idle' LPSTAT_V='' \
  PATH="$bin:$SAFE" MANUAL_STEPS_OPEN_TTY=1 MANUAL_STEPS_LIST="$tmp/steps.list" \
  "$MS" open)"
has "open shows the step when the printer is missing" "Add the home printer HP ENVY 6000 series" "$open_out"
has "open says not set yet" "NOTSET:" "$open_out"
has "open says it can only be added at home" "home network" "$open_out"
has "open names Printers and Scanners" "Printers & Scanners" "$open_out"

open_ok="$(printf 's\n' | LPSTAT_P='printer HP_ENVY_6000_series is idle' \
  PATH="$bin:$SAFE" MANUAL_STEPS_OPEN_TTY=1 MANUAL_STEPS_LIST="$tmp/steps.list" \
  "$MS" open)"
has "open skips a printer that is already there" "Nothing to do" "$open_ok"
miss "open hides the title when the printer is already there" "Add the home printer" "$open_ok"

printf 'home-printer tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
