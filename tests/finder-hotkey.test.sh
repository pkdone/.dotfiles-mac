#!/usr/bin/env bash
#
# Finder's bring-to-front hotkey lives in hammerspoon/finder_hotkey.lua
# (Shift+Control+Command+F). The Lua spec checks the binding with a stub
# hs table. The shell checks wire it into init.lua and keep it out of the
# Raycast checklist. Plain Lua only: running the spec inside Hammerspoon's
# hs CLI would replace the live hs table. With no Lua interpreter the spec
# is skipped and the doc checks still run.
# Run: ./tests/finder-hotkey.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="$DIR/lib/manual-steps.list"

pass=0
fail=0
eq() {  # description expected actual
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"
  fi
}
has() {  # description needle haystack
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n' "$1" "$2" ;; esac
}
miss() {  # description needle haystack
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n' "$1" "$2" ;;
    *) pass=$((pass + 1)) ;; esac
}

# ---- Lua spec (plain interpreter; never the live Hammerspoon hs CLI) ----
LUA=""
for c in lua5.4 lua54 lua; do
  if command -v "$c" >/dev/null 2>&1; then LUA="$c"; break; fi
done
if [ -n "$LUA" ]; then
  out="$("$LUA" "$DIR/tests/finder_hotkey_spec.lua" "$DIR" 2>&1)" || true
  printf '%s\n' "$out" | grep -v '^-- Loading extension' || true
  case "$out" in
    *"finder hotkey tests: "*" passed, 0 failed"*) pass=$((pass + 1)) ;;
    *) fail=$((fail + 1)); printf 'FAIL: finder hotkey lua spec\n%s\n' "$out" ;;
  esac
else
  echo "finder hotkey lua spec: no Lua interpreter, skipped"
fi

# ---- module is loaded with the others ----
init="$(cat "$DIR/hammerspoon/init.lua")"
has "init.lua loads finder_hotkey" "'finder_hotkey'" "$init"
src="$(cat "$DIR/hammerspoon/finder_hotkey.lua")"
has "module focuses Finder by name" 'hs.application.launchOrFocus(M.app)' "$src"
has "module binds the hotkey" 'hs.hotkey.bind(M.mods, M.key, M.press)' "$src"

# ---- Raycast no longer owns the hotkey; the clash note stays ----
list="$(cat "$LIST")"
miss "old Raycast Finder hotkey step is gone" "raycast-finder-hotkey|" "$list"
has "unbind note is a manual step" \
  "raycast-finder-unbind|App settings|Only if you imported a backup: if it still has a Finder hotkey on Shift+Control+Command+F, unbind it so it doesn't clash with Hammerspoon|" \
  "$list"
has "Raycast launcher hotkey stays" \
  "raycast-hotkey|App settings|Raycast hotkey: Shift+Control+Command+R (off Option+Space, which clashes with ChatGPT)|" \
  "$list"
has "Clipboard History stays" \
  "raycast-clipboard|App settings|Raycast Clipboard History: hotkey Control+Command+V, keep history 1 day, disable 1Password and 1Password for Safari|" \
  "$list"
miss "import step no longer says three Raycast items" "three Raycast items" "$list"

docs="$(cat "$DIR/README.md" "$DIR/SHORTCUTS.md" "$DIR"/docs/*.md "$LIST")"
miss "docs do not tell you to set a Raycast Finder hotkey" "Raycast: Finder hotkey" "$docs"
miss "shortcuts do not list Finder via Raycast" "Activate Finder (via Raycast)" "$docs"
miss "settings do not walk through recording the Finder hotkey in Raycast" \
  "activating Finder from anywhere" "$docs"
miss "Show Finder is not described as the Raycast hotkey" \
  "same keys as the Raycast Finder hotkey" "$docs"

shortcuts="$(cat "$DIR/SHORTCUTS.md")"
has "shortcuts have a Hammerspoon heading" $'#### Hammerspoon\n' "$shortcuts"
has "shortcuts list the Finder hotkey" \
  "| Bring Finder to the front | Shift + Control + Command + F |" "$shortcuts"
# The heading comes before the row, so the row sits under Hammerspoon.
hs_section="$(printf '%s\n' "$shortcuts" | awk '
  $0 == "#### Hammerspoon" { grab = 1; next }
  grab && $0 ~ /^#### / { exit }
  grab { print }
')"
has "Finder row is under the Hammerspoon heading" \
  "Bring Finder to the front" "$hs_section"
miss "Hammerspoon section does not claim Raycast" "via Raycast" "$hs_section"

printf 'finder-hotkey tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
