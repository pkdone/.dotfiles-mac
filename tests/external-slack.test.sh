#!/usr/bin/env bash
#
# Slack follows the ARZOPA portable monitor. The Lua spec drives the module
# with a stub hs table. Plain Lua only: running the spec inside Hammerspoon's
# hs CLI would replace the live hs table. With no Lua interpreter the spec
# is skipped and the source checks still run.
# Run: ./tests/external-slack.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0
eq() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"
  fi
}
has() {
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n' "$1" "$2" ;; esac
}
miss() {
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n' "$1" "$2" ;;
    *) pass=$((pass + 1)) ;; esac
}

LUA=""
for c in lua5.4 lua54 lua; do
  if command -v "$c" >/dev/null 2>&1; then LUA="$c"; break; fi
done
if [ -n "$LUA" ]; then
  out="$("$LUA" "$DIR/tests/external_slack_spec.lua" "$DIR" 2>&1)" || true
  printf '%s\n' "$out"
  case "$out" in
    *"external slack tests: "*" passed, 0 failed"*) pass=$((pass + 1)) ;;
    *) fail=$((fail + 1)); printf 'FAIL: external slack lua spec\n%s\n' "$out" ;;
  esac
else
  echo "external slack lua spec: no Lua interpreter, skipped"
fi

init="$(cat "$DIR/hammerspoon/init.lua")"
has "init.lua loads external_slack" "'external_slack'" "$init"
src="$(cat "$DIR/hammerspoon/external_slack.lua")"
has "module watches screens" 'hs.screen.watcher.new' "$src"
has "module binds the hotkey" 'hs.hotkey.bind(M.mods, M.key, M.toggle)' "$src"
has "the screen name lives in one place" "M.screenName = 'ARZOPA'" "$src"
miss "module does not send zoom keys" 'keyStroke' "$src"
miss "module does not track zoom" 'zoomed' "$src"
miss "module does not move the menu bar" 'setPrimary' "$src"
list_name="$(awk -F'|' '$1 == "external" { print $2; exit }' "$DIR/lib/display-resolution.list")"
eq "Hammerspoon and the display list use the same name" "ARZOPA" "$list_name"

shortcuts="$(cat "$DIR/SHORTCUTS.md")"
has "shortcuts list the Slack hotkey" \
  "| Move Slack onto the ARZOPA display, or bring it back | Shift + Control + Option + Command + S |" \
  "$shortcuts"

# The old iPad display name must not remain anywhere in the tree.
old="$(printf '%s%s' side car)"
hits="$(grep -R -i -n --exclude-dir=.git "$old" "$DIR" || true)"
eq "old iPad display name is gone" "" "$hits"

printf 'external-slack tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
