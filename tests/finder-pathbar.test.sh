#!/usr/bin/env bash
#
# Finder path bar: the ShowPathbar row in lib/macos-defaults.list, the how-to
# in SHORTCUTS.md and docs/settings.md, and no Option + Command + C tip
# (that shortcut did not copy a path on this Mac). Run: ./tests/finder-pathbar.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="$DIR/lib/macos-defaults.list"
SHORTCUTS="$DIR/SHORTCUTS.md"
SETTINGS="$DIR/docs/settings.md"
MACOS="$DIR/macos.sh"

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

rows="$(grep -vE '^[[:space:]]*(#|$)' "$LIST")"
field() {  # domain key field-number (1-based)
  awk -F'|' -v d="$1" -v k="$2" -v f="$3" '$1 == d && $2 == k { print $f; exit }' "$LIST"
}

has "defaults row com.apple.finder|ShowPathbar" \
  'com.apple.finder|ShowPathbar|bool|true|Finder|Finder|Show Path Bar|' "$rows"
eq "path bar is bool true" true "$(field com.apple.finder ShowPathbar 4)"
eq "path bar type is bool" bool "$(field com.apple.finder ShowPathbar 3)"
eq "path bar restarts Finder" Finder "$(field com.apple.finder ShowPathbar 5)"
eq "status bar still restarts Finder" Finder "$(field com.apple.finder ShowStatusBar 5)"

has "autofix defaults row covers Finder chrome" "Finder" \
  "$(awk -F'|' '$1=="defaults" { print; exit }' "$DIR/lib/autofix.list")"
has "settings names the ShowPathbar key" "ShowPathbar" "$(cat "$SETTINGS")"
has "settings has the path-bar copy tip" 'Copy "…" as Pathname' "$(cat "$SETTINGS")"
has "settings names View → Show Path Bar" "View → Show Path Bar" "$(cat "$SETTINGS")"

section="$(awk '/^#### Finder$/{p=1; next} /^#### /{p=0} p' "$SHORTCUTS")"
has "shortcuts mention the path bar" "path bar" "$section"
has "shortcuts name ShowPathbar" "ShowPathbar" "$section"
has "shortcuts have the Option right-click tip" 'Copy "…" as Pathname' "$section"
has "shortcuts name View → Show Path Bar" "View → Show Path Bar" "$section"
miss "shortcuts do not mention Option + Command + C" "Option + Command + C" "$(cat "$SHORTCUTS")"
miss "shortcuts do not mention the Option-C glyph" "⌥⌘C" "$(cat "$SHORTCUTS")"
miss "shortcuts Finder section has no raw <" "<" "$section"
miss "shortcuts Finder section has no raw >" ">" "$section"

# shellcheck disable=SC2016  # needle is Markdown from macos.sh --list, compared literally
has "list prints Show Path Bar" \
  '| Finder | Show Path Bar | `com.apple.finder ShowPathbar` | `true` (On) |' \
  "$("$MACOS" --list)"

printf 'OK %s  FAIL %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
