#!/usr/bin/env bash
#
# checks/modes.sh requires the Focus Shortcuts named in hammerspoon/modes.lua.
# It does not require "Mode Upcoming Meetings": that Shortcut was only for the
# DeepWork meeting alerts removed in PR #2, and nothing runs it any more.
# A WhatsApp Web quit recorded in state.json is listed by its display name
# and is not drift. The bundle id is per Mac, so modes.lua stores the app path.
# Run: ./tests/modes-check.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0
eq() {  # description expected actual
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"
  fi
}
has() {  # description needle haystack
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;; esac
}
miss() {  # description needle haystack
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n' "$1" "$2" ;;
    *) pass=$((pass + 1)) ;; esac
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/shortcuts" <<'EOF'
#!/bin/sh
if [ "${1:-}" != "list" ]; then
  echo "unexpected shortcuts args: $*" >&2
  exit 1
fi
cat "${SHORTCUTS_NAMES:?}"
EOF
chmod +x "$tmp/bin/shortcuts"

printf '%s\n' \
  'Mode WebConf On' \
  'Mode WebConf Off' \
  'Mode DeepWork On' \
  'Mode DeepWork Off' > "$tmp/four"
printf '%s\n' \
  'Mode WebConf Off' \
  'Mode DeepWork On' \
  'Mode DeepWork Off' > "$tmp/missing-on"

# $1 is the file `shortcuts list` prints.
run_focus_shortcuts() {
  SHORTCUTS_NAMES="$1" \
  PATH="$tmp/bin:$PATH" \
  DOTDIR="$DIR" \
  CHECKED=0 \
  MACCONFIG_CHECKS_DEFINE_ONLY=1 \
  bash -c '
    pass() { printf "ok|%s\n" "$1"; }
    warn() { printf "warn|%s\n" "$1"; }
    bad() { printf "warn|%s\n" "$1"; }
    info() { :; }
    note() { :; }
    fixid() { :; }
    hdr() { :; }
    with_timeout() { shift; "$@"; }
    # shellcheck disable=SC1091
    . "$DOTDIR/checks/modes.sh"
    check_step_mode_focus_shortcuts
  '
}

four="$(run_focus_shortcuts "$tmp/four")"
eq "four Focus Shortcuts pass without Mode Upcoming Meetings" \
  "ok|Focus Shortcuts exist (4)" "$four"
miss "a passing modes check does not name Mode Upcoming Meetings" \
  "Mode Upcoming Meetings" "$four"

missing="$(run_focus_shortcuts "$tmp/missing-on")"
has "a missing Focus Shortcut still warns" "warn|Shortcuts missing:" "$missing"
has "the warning names the missing Focus Shortcut" "'Mode WebConf On'" "$missing"
miss "the warning does not require Mode Upcoming Meetings" \
  "Mode Upcoming Meetings" "$missing"

miss "modes check source does not require Mode Upcoming Meetings" \
  "Mode Upcoming Meetings" "$(cat "$DIR/checks/modes.sh")"

modes_src="$(cat "$DIR/hammerspoon/modes.lua")"
eq "WhatsApp Web is named by its app path" \
  "1" "$(printf '%s\n' "$modes_src" | grep -c "path = '~/Applications/WhatsApp Web.app'" || true)"
eq "WebConf and DeepWork both quit WhatsApp Web" \
  "2" "$(printf '%s\n' "$modes_src" | grep -c 'apps\.whatsappWeb' || true)"
eq "modes do not store a Safari web app UUID" "" \
  "$(grep -RInE 'com\.apple\.(Safari|safari)\.WebApp\.[0-9A-Fa-f]{8}-' \
    "$DIR/hammerspoon" "$DIR/docs/modes.md" || true)"
has "the switcher reads the bundle id from the app" "infoForBundlePath" \
  "$(cat "$DIR/hammerspoon/mode_switcher.lua")"

# state.json records the display name. The check lists that name and does not
# treat a quit WhatsApp Web as drift.
state_home="$tmp/wa-home"
mkdir -p "$state_home/Library/Application Support/pdone-modes"
python3 - "$state_home/Library/Application Support/pdone-modes/state.json" <<'PY'
import json, sys, time
json.dump({
    "version": 1,
    "mode": "WebConf",
    "since": time.time(),
    "phase": "applied",
    "changes": {
        "quit": [{
            "bundle": "com.apple.Safari.WebApp.11111111-2222-3333-4444-555555555555",
            "name": "WhatsApp Web",
            "path": "/tmp/Applications/WhatsApp Web.app",
            "app": "~/Applications/WhatsApp Web.app",
        }]
    },
}, open(sys.argv[1], "w"))
PY
wa_modes="$(
  SHORTCUTS_NAMES="$tmp/four" \
  PATH="$tmp/bin:$PATH" \
  HOME="$state_home" \
  DOTDIR="$DIR" \
  DOT_PYTHON="$(command -v python3)" \
  CHECKED=0 \
  bash -c '
    pass() { printf "ok|%s\n" "$1"; }
    warn() { printf "warn|%s\n" "$1"; }
    bad() { printf "bad|%s\n" "$1"; }
    info() { printf "info|%s\n" "$1"; }
    note() { printf "note|%s\n" "$1"; }
    fixid() { :; }
    hdr() { :; }
    with_timeout() { shift; "$@"; }
    # shellcheck disable=SC1091
    . "$DOTDIR/checks/modes.sh"
  '
)"
has "a quit WhatsApp Web is listed by name" \
  "note|quit by WebConf on purpose (not drift; Normal reopens them): WhatsApp Web" \
  "$wa_modes"
miss "a quit WhatsApp Web is not drift" "bad|" "$wa_modes"
has "modes.lua still validates" "ok|hammerspoon/modes.lua is valid" "$wa_modes"

printf 'modes-check tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
