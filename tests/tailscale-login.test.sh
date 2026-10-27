#!/usr/bin/env bash
#
# Tailscale Open at Login. Reads System Events login-item names and the BTM
# app record. Does not add the item. An uninstalled app is left alone.
# Run: ./tests/tailscale-login.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hermetic.sh disable=SC1091
. "$DIR/tests/hermetic.sh"
LIST="$DIR/lib/manual-steps.list"
MS="$DIR/scripts/manual-steps.sh"
PY="$(command -v python3 || true)"
export NO_COLOR=1

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

HOW="System Settings → General → Login Items & Extensions → under Open at Login click + → Applications → Tailscale → Open"
row="$(awk -F'|' '$1=="tailscale-login" { print; exit }' "$LIST")"
eq "step title" "Add Tailscale to Open at Login. It has no launch-at-login option of its own" \
  "$(printf '%s\n' "$row" | cut -d'|' -f3)"
eq "step where" "$HOW" "$(printf '%s\n' "$row" | cut -d'|' -f4)"
eq "step group" "Sign-ins" "$(printf '%s\n' "$row" | cut -d'|' -f2)"
eq "step is checked with login items" "@macconfig:login-items" \
  "$(printf '%s\n' "$row" | cut -d'|' -f6)"
order="$(awk -F'|' '$1=="tailscale-signin" || $1=="tailscale-login" { print $1 }' "$LIST" | tr '\n' ' ')"
eq "Open at Login follows the Tailscale sign-in" "tailscale-signin tailscale-login " "$order"

has "allow list has Tailscale's team" "team|W5364U7YZB|" "$(cat "$DIR/lib/login-items-allow.list")"
has "allow list has the standalone bundle" "bundle|io.tailscale.ipn.macsys|" \
  "$(cat "$DIR/lib/login-items-allow.list")"
if [ -n "$PY" ]; then
  allowed="$("$PY" - "$DIR/lib/btm-login-items.py" "$DIR/lib/login-items-allow.list" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("btm", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
rules = mod.read_allow(sys.argv[2])
item = {
    "bundle": "io.tailscale.ipn.macsys",
    "team": "W5364U7YZB",
    "id": "io.tailscale.ipn.macsys",
    "parent": "",
    "name": "Tailscale",
    "identifier": "2.io.tailscale.ipn.macsys",
    "url": "file:///Applications/Tailscale.app",
    "executable": "",
}
print("yes" if any(mod.matches(rule, item) for rule in rules) else "no")
named = dict(item)
named["bundle"] = ""
named["team"] = "W5364U7YZB"
print("yes" if any(mod.matches(rule, named) for rule in rules) else "no")
PY
)"
  eq "bundle record is allow-listed" "yes" "$(printf '%s\n' "$allowed" | sed -n '1p')"
  eq "team record is allow-listed" "yes" "$(printf '%s\n' "$allowed" | sed -n '2p')"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/app/Contents" "$tmp/home"
cat > "$tmp/bin/osascript" <<'EOF'
#!/bin/sh
if [ "${OSASCRIPT_RC:-0}" -ne 0 ]; then
  exit "$OSASCRIPT_RC"
fi
printf '%s\n' "${LOGIN_ITEMS-}"
EOF
cat > "$tmp/bin/python3" <<'EOF'
#!/bin/sh
if [ "$1" = "-c" ]; then
  printf '%s\n' "io.tailscale.ipn.macsys"
  exit 0
fi
printf '%s\n' "io.tailscale.ipn.macsys=${BTM_STATUS:-missing}"
exit "${BTM_RC:-0}"
EOF
cat > "$tmp/bin/open" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$tmp/bin/mdfind" <<'EOF'
#!/bin/sh
# Spotlight must not report a host Tailscale (bundle id or /Applications path).
exit 0
EOF
cat > "$tmp/bin/defaults" <<'EOF'
#!/bin/sh
exit 1
EOF
cat > "$tmp/bin/sfltool" <<'EOF'
#!/bin/sh
echo "sfltool should not be run" >&2
exit 1
EOF
chmod +x "$tmp/bin/osascript" "$tmp/bin/python3" "$tmp/bin/open" "$tmp/bin/mdfind" \
  "$tmp/bin/defaults" "$tmp/bin/sfltool"
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
    TAILSCALE_APP_PATH="$tmp/app" \
    DOT_PYTHON="$tmp/bin/python3" \
    DOTDIR="$DIR" \
    LOGIN_ITEMS="${1-}" \
    OSASCRIPT_RC="${2:-0}" \
    BTM_STATUS="${3:-missing}" \
    BTM_RC="${4:-0}" \
    check_step_tailscale_login
  printf '%s' "$lines"
}

out="$(run_check "Google Chrome, Granola, Grok Bot, Hammerspoon, Okta Verify, Raycast, Slack, Tailscale")"
eq "a listed Tailscale passes" "ok" "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "a listed Tailscale says it is in Open at Login" "Tailscale is in Open at Login" "$out"
# run_check prints from a subshell, so the count is read from a direct call.
CHECKED=0
lines=""
PATH="$tmp/bin:$PATH" TAILSCALE_APP_PATH="$tmp/app" DOT_PYTHON="$tmp/bin/python3" DOTDIR="$DIR" \
  LOGIN_ITEMS="Google Chrome, Slack, Tailscale" OSASCRIPT_RC=0 BTM_STATUS=missing BTM_RC=0 \
  check_step_tailscale_login
eq "a listed Tailscale is counted" "1" "$CHECKED"

out="$(run_check "Google Chrome, Slack")"
eq "a missing Tailscale warns" "warn" "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "a missing Tailscale gives the click path" "$HOW" "$out"
miss "a missing Tailscale is not drift" "bad|" "$out"

out="$(run_check "" 1 enabled)"
eq "BTM enabled counts when the name list cannot be read" "ok" \
  "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"

out="$(run_check "" 1 missing)"
eq "an unreadable list is not a false missing warning" "info" \
  "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "an unreadable list stays by hand" "stays by hand" "$out"
CHECKED=0
lines=""
PATH="$tmp/bin:$PATH" TAILSCALE_APP_PATH="$tmp/app" DOT_PYTHON="$tmp/bin/python3" DOTDIR="$DIR" \
  LOGIN_ITEMS="" OSASCRIPT_RC=1 BTM_STATUS=missing BTM_RC=0 \
  check_step_tailscale_login
eq "an unreadable list is not part of the ok total" "0" "$CHECKED"

lines=""
CHECKED=0
TAILSCALE_APP_PATH="$tmp/no-such-app" PATH="$tmp/bin:$PATH" DOT_PYTHON="$tmp/bin/python3" DOTDIR="$DIR" \
  check_step_tailscale_login
out="$lines"
eq "a missing app is left alone" "skip" "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
eq "a missing app is not counted" "0" "$CHECKED"
miss "a missing app is not a warning" "warn|" "$out"
has "a missing app says it is not installed yet" "not installed yet" "$out"

miss "the check does not add a login item" "make new login item" "$(cat "$DIR/checks/login-items.sh")"
miss "the login-items section does not invoke sfltool" "sfltool" \
  "$(grep -vE '^[[:space:]]*#' "$DIR/checks/login-items.sh" || true)"

printf '%s\n' \
  'tailscale-login|Sign-ins|Add Tailscale to Open at Login|'"$HOW"'|x-apple.systempreferences:com.apple.LoginItems-Settings.extension|@macconfig:login-items' \
  > "$tmp/step.list"
# Uninstalled: every lookup the check can make stays inside $tmp. The app
# path (TAILSCALE_APP_PATH, else /Applications/Tailscale.app), Spotlight,
# the bundle id, login items, defaults, and HOME must not be the machine
# this runs on. The safe PATH keeps host commands (defaults, dscl, osascript,
# tailscale) invisible and still has awk and perl for with_timeout.
hermetic_path="$tmp/bin:$(hermetic_safe_root)"
open_out="$(printf 's\n' | env -u LOGIN_ITEMS -u BTM_STATUS -u BTM_RC -u OSASCRIPT_RC \
  PATH="$hermetic_path" HOME="$tmp/home" NO_COLOR=1 \
  MANUAL_STEPS_OPEN_TTY=1 MANUAL_STEPS_LIST="$tmp/step.list" \
  DOT_PYTHON="$tmp/bin/python3" \
  TAILSCALE_APP_PATH="$tmp/no-such-app" \
  MANUAL_STEPS_TAILSCALE_BIN="$tmp/no-such-tailscale" \
  "$MS" open 2>"$tmp/open.err")"
eq "open stderr stays empty when Tailscale is not installed" "" "$(cat "$tmp/open.err")"
has "an uninstalled Tailscale is not walked" "Nothing to do" "$open_out"

# Installed but missing from the list: NOTSET and the click path.
mkdir -p "$tmp/real-app/Contents"
cp "$tmp/app/Contents/Info.plist" "$tmp/real-app/Contents/Info.plist"
# The check's default path is /Applications/Tailscale.app. Override it by
# running the step function, which is what @macconfig calls, and format the
# reason the way open does.
# shellcheck source=../lib/why-shown.sh disable=SC1091
. "$DIR/lib/why-shown.sh"
lines=""
TAILSCALE_APP_PATH="$tmp/real-app" PATH="$tmp/bin:$PATH" DOT_PYTHON="$tmp/bin/python3" \
  DOTDIR="$DIR" LOGIN_ITEMS="Slack" OSASCRIPT_RC=0 BTM_STATUS=missing \
  check_step_tailscale_login
why="$(why_shown_line warn "$(printf '%s\n' "$lines" | sed -n 's/^warn|//p')")"
has "a missing login item is NOTSET" "NOTSET:" "$why"
has "NOTSET keeps the click path" "click +" "$why"

printf 'tailscale-login tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
