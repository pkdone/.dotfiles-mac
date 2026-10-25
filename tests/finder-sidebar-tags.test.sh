#!/usr/bin/env bash
#
# No tags in the Finder sidebar is a manual step. FavoriteTagNames is not a
# pass/fail signal: on pdone-mac2 every box is unticked and the sidebar has
# no Tags section, but the key still lists tag names (iCloud sync).
# Run: ./tests/finder-sidebar-tags.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="$DIR/lib/manual-steps.list"
MS="$DIR/scripts/manual-steps.sh"
CHECK="$DIR/checks/finder.sh"
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

row="$(awk -F'|' '$1=="finder-sidebar-tags" { print; exit }' "$LIST")"
eq "tags step exists" 1 "$(printf '%s\n' "$row" | grep -c .)"
eq "tags step group" "Login Items & Finder" "$(printf '%s\n' "$row" | cut -d'|' -f2)"
eq "tags step title" "No tags shown in the sidebar" "$(printf '%s\n' "$row" | cut -d'|' -f3)"
eq "tags step where" \
  "Finder → Settings → Tags → untick every box under Show these tags in the sidebar" \
  "$(printf '%s\n' "$row" | cut -d'|' -f4)"
eq "tags step check is empty" "" "$(printf '%s\n' "$row" | cut -d'|' -f6)"
prev="$(awk -F'|' '
  $1 ~ /^#/ || $1 ~ /^[[:space:]]*$/ { next }
  $1 == "finder-sidebar-tags" { print prev; exit }
  { prev = $1 }
' "$LIST")"
eq "tags step follows the checked sidebar rows" "finder-sidebar" "$prev"

sidebar_title="$(awk -F'|' '$1=="finder-sidebar" { print $3; exit }' "$LIST")"
miss "checked sidebar step does not claim the tags are verified" "No tags" "$sidebar_title"
has "checked sidebar step still names the rows" "Recents and Shared stay hidden" "$sidebar_title"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '%s\n' "$row" > "$tmp/tags.list"
pending="$(MANUAL_STEPS_LIST="$tmp/tags.list" "$MS" pending 2>"$tmp/pending.err")"
has "tags step is MANUAL" \
  "MANUAL: Can't check this automatically. If it's already set, press s." "$pending"
miss "tags step is not NOTSET" "NOTSET:" "$pending"
eq "tags pending stderr stays empty" "" "$(cat "$tmp/pending.err")"

check_code="$(grep -vE '^[[:space:]]*#' "$CHECK" || true)"
miss "finder check code does not read FavoriteTagNames" "FavoriteTagNames" "$check_code"
miss "finder check does not run the old tag helper" "finder-sidebar-tags.py" "$(cat "$CHECK")"
miss "finder check does not warn that tags are still shown" "These tags are still shown" "$(cat "$CHECK")"
miss "old tag helper is gone" "finder-sidebar-tags.py" "$(ls "$DIR/lib")"

eq "shared row is still hidden" "hidden" \
  "$(awk -F'|' '$1=="shared" { print $3; exit }' "$DIR/lib/finder-sidebar-rows.list")"
has "favorites list still includes Developer" "Developer|@HOME@/Developer" \
  "$(cat "$DIR/lib/sidebar-favorites.list")"
miss "autofix does not treat FavoriteTagNames as the tags check" "FavoriteTagNames empty" \
  "$(awk -F'|' '$1=="finder-sidebar" { print; exit }' "$DIR/lib/autofix.list")"

printf 'finder-sidebar-tags tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
