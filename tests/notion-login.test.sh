#!/usr/bin/env bash
#
# Notion Open at Login. Reads System Events login-item names and the BTM
# app record. Does not add the item. An uninstalled app is left alone.
# There is no manual step: Notion registers itself, like Slack, Ghostty,
# and Raycast. Run: ./tests/notion-login.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hermetic.sh disable=SC1091
. "$DIR/tests/hermetic.sh"

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

HOW="System Settings → General → Login Items & Extensions → under Open at Login click + → Applications → Notion → Open"

has "allow list expects Notion at login" "bundle|notion.id|Notion opens at login" \
  "$(cat "$DIR/lib/login-items-allow.list")"
has "notion cask is in the Brewfile" 'cask "notion"' "$(cat "$DIR/Brewfile")"
miss "no Notion open-at-login manual step" "notion|" \
  "$(grep -v '^#' "$DIR/lib/manual-steps.list" || true)"
has "settings says Notion must be in Open at Login" \
  "must be in Open at Login, the same way Slack, Ghostty, and Raycast are" \
  "$(cat "$DIR/docs/settings.md")"
has "settings gives the click path for a missing Notion" "$HOW" \
  "$(cat "$DIR/docs/settings.md")"
has "settings says there is no setter and no bootstrap step" \
  "There is no setter and no bootstrap step" "$(cat "$DIR/docs/settings.md")"
has "autofix mentions Notion stays in Open at Login" \
  "Tailscale and Notion stay in Open at Login" "$(cat "$DIR/lib/autofix.list")"

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
  printf '%s\n' "notion.id"
  exit 0
fi
printf '%s\n' "notion.id=${BTM_STATUS:-missing}"
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
    NOTION_APP_PATH="$tmp/app" \
    DOT_PYTHON="$tmp/bin/python3" \
    DOTDIR="$DIR" \
    LOGIN_ITEMS="${1-}" \
    OSASCRIPT_RC="${2:-0}" \
    BTM_STATUS="${3:-missing}" \
    BTM_RC="${4:-0}" \
    check_step_notion_login
  printf '%s' "$lines"
}

out="$(run_check "Google Chrome, Granola, Grok Bot, Hammerspoon, Notion, Raycast, Slack, Tailscale")"
eq "a listed Notion passes" "ok" "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "a listed Notion says it is in Open at Login" "Notion is in Open at Login" "$out"
CHECKED=0
lines=""
PATH="$tmp/bin:$PATH" NOTION_APP_PATH="$tmp/app" DOT_PYTHON="$tmp/bin/python3" DOTDIR="$DIR" \
  LOGIN_ITEMS="Google Chrome, Notion, Slack" OSASCRIPT_RC=0 BTM_STATUS=missing BTM_RC=0 \
  check_step_notion_login
eq "a listed Notion is counted" "1" "$CHECKED"

out="$(run_check "Google Chrome, Slack")"
eq "a missing Notion warns" "warn" "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "a missing Notion gives the click path" "$HOW" "$out"
miss "a missing Notion is not drift" "bad|" "$out"

out="$(run_check "" 1 enabled)"
eq "BTM enabled counts when the name list cannot be read" "ok" \
  "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"

out="$(run_check "" 1 missing)"
eq "an unreadable list is not a false missing warning" "info" \
  "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "an unreadable list stays by hand" "stays by hand" "$out"
CHECKED=0
lines=""
PATH="$tmp/bin:$PATH" NOTION_APP_PATH="$tmp/app" DOT_PYTHON="$tmp/bin/python3" DOTDIR="$DIR" \
  LOGIN_ITEMS="" OSASCRIPT_RC=1 BTM_STATUS=missing BTM_RC=0 \
  check_step_notion_login
eq "an unreadable list is not part of the ok total" "0" "$CHECKED"

out="$(run_check "Google Chrome, Slack" 0 disabled)"
eq "BTM disabled warns when the classic list has no Notion" "warn" \
  "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"

lines=""
CHECKED=0
NOTION_APP_PATH="$tmp/no-such-app" PATH="$tmp/bin:$PATH" DOT_PYTHON="$tmp/bin/python3" DOTDIR="$DIR" \
  check_step_notion_login
out="$lines"
eq "a missing app is left alone" "skip" "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
eq "a missing app is not counted" "0" "$CHECKED"
miss "a missing app is not a warning" "warn|" "$out"
has "a missing app says it is not installed yet" "not installed yet" "$out"

miss "the check does not add a login item" "make new login item" "$(cat "$DIR/checks/login-items.sh")"
miss "the login-items section does not invoke sfltool" "sfltool" \
  "$(grep -vE '^[[:space:]]*#' "$DIR/checks/login-items.sh" || true)"
has "Login Items runs the Notion check" "check_step_notion_login" \
  "$(cat "$DIR/checks/login-items.sh")"
miss "bootstrap does not add login items" "make login item" \
  "$(grep -vE '^[[:space:]]*#' "$DIR/bootstrap.sh" "$DIR/install.sh" "$DIR/checks/login-items.sh" || true)"

printf 'notion-login tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
