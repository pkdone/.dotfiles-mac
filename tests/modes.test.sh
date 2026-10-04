#!/usr/bin/env bash
#
# Tests for hammerspoon/modes.lua (structure) and the pure planning logic in
# hammerspoon/mode_switcher.lua (tests/modes_spec.lua). Uses a Lua 5.4 interpreter if
# there is one (CI installs lua5.4), else the running Hammerspoon via its `hs` CLI,
# else skips. Run: ./tests/modes.test.sh   (exits non-zero if any assertion fails)
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA=""
for c in lua5.4 lua54 lua; do
  if command -v "$c" >/dev/null 2>&1; then LUA="$c"; break; fi
done

if [ -n "$LUA" ]; then
  out="$("$LUA" "$DIR/tests/modes_spec.lua" "$DIR" 2>&1)"
elif command -v hs >/dev/null 2>&1 && pgrep -xq Hammerspoon; then
  # hs reads stdin when it isn't a terminal, so give it /dev/null; perl alarm = timeout.
  out="$(perl -e 'alarm 30; exec @ARGV' hs -q -t 20 -c "MODES_TEST_DIR = '$DIR'; return dofile('$DIR/tests/modes_spec.lua')" </dev/null 2>&1)"
else
  echo "modes tests: no Lua interpreter and Hammerspoon not running, skipped"
  exit 0
fi
printf '%s\n' "$out" | grep -v '^-- Loading extension'
case "$out" in
  *"modes tests: "*" passed, 0 failed"*) exit 0 ;;
  *) exit 1 ;;
esac
