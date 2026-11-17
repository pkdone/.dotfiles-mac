#!/usr/bin/env bash
#
# Granola must not be in Open at Login. Reads System Events login-item
# names and the BTM app record. Does not add or remove the item. An
# uninstalled app is left alone. The app stays installed when present.
# Run: ./tests/granola-login.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hermetic.sh disable=SC1091
. "$DIR/tests/hermetic.sh"
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

HOW="Granola → Preferences → General → turn off Open Granola when you log in (macOS may ask for Touch ID or your password). Also System Settings → General → Login Items & Extensions → Open at Login → Granola Off. The app stays installed"
row="$(awk -F'|' '$1=="granola-login" { print; exit }' "$LIST")"
has "step title starts by stopping open at login" "Stop Granola opening at login. Leave the app installed." \
  "$(printf '%s\n' "$row" | cut -d'|' -f3)"
eq "step group" "Login Items & Finder" "$(printf '%s\n' "$row" | cut -d'|' -f2)"
eq "step opens Granola" "app:Granola" "$(printf '%s\n' "$row" | cut -d'|' -f5)"
eq "step is checked with login items" "@macconfig:login-items" \
  "$(printf '%s\n' "$row" | cut -d'|' -f6)"
has "step where names the in-app switch" "Open Granola when you log in" \
  "$(printf '%s\n' "$row" | cut -d'|' -f4)"
has "step where names System Settings" "Login Items & Extensions" \
  "$(printf '%s\n' "$row" | cut -d'|' -f4)"

miss "allow list does not expect Granola at login" "bundle|com.granola.app|" \
  "$(grep -v '^#' "$DIR/lib/login-items-allow.list" || true)"
has "granola cask stays in the Brewfile" 'cask "granola"' "$(cat "$DIR/Brewfile")"
miss "Granola is not an unwanted app" "Granola" \
  "$(grep -v '^#' "$DIR/lib/unwanted-apps.list" || true)"
miss "dock list does not pin Granola" $'Granola|' "$(cat "$DIR/lib/dock-apps.list")"
has "settings says Granola stays installed and not in Open at Login" \
  "must not be in Open at Login" "$(cat "$DIR/docs/settings.md")"
has "setup keeps Granola on Desktop 1 but not in the Dock" \
  "Granola stays installed (Brewfile cask \`granola\`) but is not in the Dock" \
  "$(cat "$DIR/docs/setup.md")"
has "troubleshooting mentions the in-app switch" \
  "Open Granola when you log in" "$(cat "$DIR/docs/troubleshooting.md")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/app/Contents" "$tmp/home"
cat > "$tmp/bin/osascript" <<'EOS'
#!/bin/sh
if [ "${OSASCRIPT_RC:-0}" -ne 0 ]; then
  exit "$OSASCRIPT_RC"
fi
printf '%s\n' "${LOGIN_ITEMS-}"
EOS
cat > "$tmp/bin/python3" <<'EOS'
#!/bin/sh
if [ "$1" = "-c" ]; then
  printf '%s\n' "com.granola.app"
  exit 0
fi
printf '%s\n' "com.granola.app=${BTM_STATUS:-missing}"
exit "${BTM_RC:-0}"
EOS
chmod +x "$tmp/bin/osascript" "$tmp/bin/python3"
printf 'bplist00' > "$tmp/app/Contents/Info.plist"

# shellcheck source=../checks/login-items.sh disable=SC1091
MACCONFIG_CHECKS_DEFINE_ONLY=1
DOTDIR="$DIR"
# shellcheck disable=SC1091
. "$DIR/checks/login-items.sh"
unset MACCONFIG_CHECKS_DEFINE_ONLY

with_timeout() { shift; "$@"; }
CHECKED=0
fixid() { :; }
lines=""
pass() { lines="${lines}ok|$1"$'\n'; }
warn() { lines="${lines}warn|$1"$'\n'; }
bad() { lines="${lines}bad|$1"$'\n'; }
info() { lines="${lines}info|$1"$'\n'; }
skip() { lines="${lines}skip|$1"$'\n'; }

run_check() {
  lines=""
  CHECKED=0
  PATH="$tmp/bin:$PATH" \
    GRANOLA_APP_PATH="$tmp/app" \
    DOT_PYTHON="$tmp/bin/python3" \
    DOTDIR="$DIR" \
    LOGIN_ITEMS="${1-}" \
    OSASCRIPT_RC="${2:-0}" \
    BTM_STATUS="${3:-missing}" \
    BTM_RC="${4:-0}" \
    check_step_granola_login
  printf '%s' "$lines"
}

out="$(run_check "Google Chrome, Granola, Grok Bot, Hammerspoon, Slack, Tailscale")"
eq "a listed Granola warns" "warn" "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "a listed Granola gives the by-hand path" "$HOW" "$out"
miss "a listed Granola is not drift" "bad|" "$out"
CHECKED=0
lines=""
PATH="$tmp/bin:$PATH" GRANOLA_APP_PATH="$tmp/app" DOT_PYTHON="$tmp/bin/python3" DOTDIR="$DIR" \
  LOGIN_ITEMS="Google Chrome, Granola, Slack" OSASCRIPT_RC=0 BTM_STATUS=missing BTM_RC=0 \
  check_step_granola_login
eq "a listed Granola is counted" "1" "$CHECKED"

out="$(run_check "Google Chrome, Slack" 0 enabled)"
eq "BTM enabled warns when the classic list has no Granola" "warn" \
  "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "a BTM-enabled Granola gives the by-hand path" "$HOW" "$out"

out="$(run_check "Google Chrome, Slack")"
eq "an absent Granola passes" "ok" "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "an absent Granola says it is not in Open at Login" "Granola is not in Open at Login" "$out"

out="$(run_check "Google Chrome, Slack" 0 disabled)"
eq "BTM disabled counts as not in Open at Login" "ok" \
  "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"

out="$(run_check "" 1 enabled)"
eq "BTM enabled counts when the name list cannot be read" "warn" \
  "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"

out="$(run_check "" 1 missing)"
eq "an unreadable list plus a missing BTM record is not a false warning" "ok" \
  "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"

out="$(run_check "Google Chrome, Slack" 0 missing 3)"
eq "an unreadable BTM store stays by hand even if the name list is clean" "info" \
  "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "an unreadable BTM store stays by hand" "stays by hand" "$out"
CHECKED=0
lines=""
PATH="$tmp/bin:$PATH" GRANOLA_APP_PATH="$tmp/app" DOT_PYTHON="$tmp/bin/python3" DOTDIR="$DIR" \
  LOGIN_ITEMS="Google Chrome, Slack" OSASCRIPT_RC=0 BTM_STATUS=missing BTM_RC=3 \
  check_step_granola_login
eq "an unreadable BTM store is not part of the ok total" "0" "$CHECKED"

out="$(run_check "" 1 missing 3)"
eq "an unreadable list and BTM store stay by hand" "info" \
  "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"

lines=""
CHECKED=0
GRANOLA_APP_PATH="$tmp/no-such-app" PATH="$tmp/bin:$PATH" DOT_PYTHON="$tmp/bin/python3" DOTDIR="$DIR" \
  check_step_granola_login
out="$lines"
eq "a missing app is left alone" "skip" "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
eq "a missing app is not counted" "0" "$CHECKED"
miss "a missing app is not a warning" "warn|" "$out"
has "a missing app says it is not installed yet" "not installed yet" "$out"

miss "the check does not add a login item" "make new login item" "$(cat "$DIR/checks/login-items.sh")"
miss "the check does not delete a login item" "delete login item" "$(cat "$DIR/checks/login-items.sh")"
miss "the login-items section does not invoke sfltool" "sfltool" \
  "$(grep -vE '^[[:space:]]*#' "$DIR/checks/login-items.sh" || true)"
has "Login Items runs the Granola check" "check_step_granola_login" \
  "$(cat "$DIR/checks/login-items.sh")"

printf 'granola-login tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
