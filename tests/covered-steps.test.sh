#!/usr/bin/env bash
#
# Manual steps whose check is @macconfig:<area> use the section's step function.
# A failing step is shown by open. A passing step is skipped. macconfig's own
# Manual steps section asks for covered so it does not count the step twice.
# Run: ./tests/covered-steps.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/Library/DoNotDisturb/DB"
cat > "$tmp/bin/open" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$tmp/bin/open"
export NO_COLOR=1
export DOTDIR="$DIR"
# shellcheck disable=SC1091
. "$DIR/lib/covered-steps.sh"

focus_db="$tmp/home/Library/DoNotDisturb/DB/ModeConfigurations.json"
one="$tmp/one.list"
printf '%s\n' \
  'mode-focus-modes|Modes|Create Focus modes|System Settings → Focus|x-apple.systempreferences:com.apple.Focus-Settings.extension|@macconfig:modes' \
  > "$one"

printf '%s\n' '{"name":"Other"}' > "$focus_db"
bad_porc="$(HOME="$tmp/home" MANUAL_STEPS_LIST="$one" "$MS" check --porcelain 2>"$tmp/bad.err")"
bad_rc=$?
eq "a missing Focus mode warns" 1 "$bad_rc"
eq "stderr stays empty" "" "$(cat "$tmp/bad.err")"
eq "porcelain status is warn" "warn" "$(printf '%s\n' "$bad_porc" | cut -d'|' -f1)"
has "porcelain detail names the missing modes" "Focus modes missing:" "$bad_porc"
has "porcelain detail names WebConf" "WebConf" "$bad_porc"

bad_open="$(printf 's\n' | HOME="$tmp/home" MANUAL_STEPS_OPEN_TTY=1 MANUAL_STEPS_LIST="$one" \
  PATH="$tmp/bin:$PATH" "$MS" open 2>"$tmp/open.err")"
has "open shows the failing step" "Create Focus modes" "$bad_open"
has "open says not set yet" "Not set yet: Focus modes missing:" "$bad_open"

section_out="$(
  CHECKED=0
  pass() { printf 'ok|%s\n' "$1"; }
  warn() { printf 'warn|%s\n' "$1"; }
  bad() { printf 'warn|%s\n' "$1"; }
  # shellcheck disable=SC2317
  info() { :; }
  # shellcheck disable=SC2317
  note() { :; }
  fixid() { :; }
  hdr() { :; }
  DOTDIR="$DIR" HOME="$tmp/home" DOT_PYTHON="$(command -v python3)" \
    MACCONFIG_CHECKS_DEFINE_ONLY=1
  # shellcheck disable=SC1091
  . "$DIR/checks/modes.sh"
  check_step_mode_focus_modes
)"
eq "section function and manualsteps agree (failing)" \
  "warn" "$(printf '%s\n' "$section_out" | head -n 1 | cut -d'|' -f1)"
eq "manualsteps status matches the section function" \
  "$(printf '%s\n' "$section_out" | head -n 1 | cut -d'|' -f1)" \
  "$(printf '%s\n' "$bad_porc" | cut -d'|' -f1)"

printf '%s\n' '{"a":{"name":"WebConf"},"b":{"name":"DeepWork"}}' > "$focus_db"
ok_porc="$(HOME="$tmp/home" MANUAL_STEPS_LIST="$one" "$MS" check --porcelain 2>"$tmp/ok.err")"
ok_rc=$?
eq "Focus modes present exits 0" 0 "$ok_rc"
eq "porcelain status is ok" "ok" "$(printf '%s\n' "$ok_porc" | cut -d'|' -f1)"
ok_open="$(printf 's\n' | HOME="$tmp/home" MANUAL_STEPS_OPEN_TTY=1 MANUAL_STEPS_LIST="$one" \
  PATH="$tmp/bin:$PATH" "$MS" open 2>"$tmp/okopen.err")"
miss "open skips a passing macconfig step" "Create Focus modes" "$ok_open"
has "open says there is nothing to do" "Nothing to do:" "$ok_open"

section_ok="$(
  CHECKED=0
  pass() { printf 'ok|%s\n' "$1"; }
  warn() { printf 'warn|%s\n' "$1"; }
  bad() { printf 'warn|%s\n' "$1"; }
  # shellcheck disable=SC2317
  info() { :; }
  # shellcheck disable=SC2317
  note() { :; }
  fixid() { :; }
  hdr() { :; }
  DOTDIR="$DIR" HOME="$tmp/home" DOT_PYTHON="$(command -v python3)" \
    MACCONFIG_CHECKS_DEFINE_ONLY=1
  # shellcheck disable=SC1091
  . "$DIR/checks/modes.sh"
  check_step_mode_focus_modes
)"
eq "section function and manualsteps agree (passing)" \
  "ok" "$(printf '%s\n' "$section_ok" | head -n 1 | cut -d'|' -f1)"

owned="$(HOME="$tmp/home" MACCONFIG_OWNS_SECTIONS=1 MANUAL_STEPS_LIST="$one" \
  "$MS" check --porcelain 2>"$tmp/owned.err")"
eq "macconfig asks for covered instead of a second result" "covered" \
  "$(printf '%s\n' "$owned" | cut -d'|' -f1)"
has "manual section sets the owns flag" "MACCONFIG_OWNS_SECTIONS=1" \
  "$(cat "$DIR/checks/manual.sh")"
has "manual section ignores covered rows" "covered|'') : ;;" \
  "$(grep -v '^[[:space:]]*#' "$DIR/checks/manual.sh")"
miss "covered-steps does not launch macconfig" "macconfig-check.sh" \
  "$(cat "$DIR/lib/covered-steps.sh")"

# Every @macconfig step: manualsteps check and the shared function agree.
awk -F'|' '$1 !~ /^#/ && $6 ~ /^@macconfig:/ { print $1, substr($6, 12) }' "$LIST" > "$tmp/ids.txt"
while read -r id area; do
  [ -n "$id" ] || continue
  printf '%s|G|Title|Where||@macconfig:%s\n' "$id" "$area" > "$tmp/row.list"
  porc="$(HOME="$tmp/home" MANUAL_STEPS_LIST="$tmp/row.list" "$MS" check --porcelain 2>/dev/null || true)"
  direct="$(HOME="$tmp/home" covered_step_run "$id" "$area" 2>/dev/null || true)"
  eq "$id status matches" \
    "$(printf '%s\n' "$direct" | cut -d'|' -f1)" \
    "$(printf '%s\n' "$porc" | cut -d'|' -f1)"
done < "$tmp/ids.txt"

# shellcheck disable=SC2016  # the needle is source text, compared literally
has "a failed step's why line is yellow" 'warn) why_c="$C_WARN"' "$(cat "$MS")"

printf 'covered-steps tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
