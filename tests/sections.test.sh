#!/usr/bin/env bash
#
# Section split: headings stay in the original order, and --only runs a subset.
# The heading list is the order macconfig-check.sh printed before the split.
# Run: ./tests/sections.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL="$DIR/macconfig-check.sh"
SHIM="$DIR/check.sh"

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
ok() {
  if [ "$2" = 0 ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s (status %s)\n' "$1" "$2"; fi
}

# Headings in source order: each sourced checks/*.sh, finder twice (icon, recents).
headings_in_source() {
  local file part
  part=""
  while IFS= read -r line; do
    # shellcheck disable=SC2016  # the needle is a source line, compared as text
    case "$line" in
      *'CHECK_PART='*)
        part="${line#*CHECK_PART=}"
        part="${part%%[!A-Za-z]*}"
        ;;
      *'unset CHECK_PART'*) part="" ;;
      *'. "$DOTDIR/checks/'*)
        file="${line#*checks/}"
        file="${file%%\"*}"
        if [ "$file" = finder.sh ]; then
          awk -v arm="$part" '
            $0 ~ "^" arm ")$" { grab=1; next }
            grab && /^;;$/ { exit }
            grab && /^[[:space:]]*hdr "/ {
              sub(/^[[:space:]]*hdr "/, "")
              sub(/"$/, "")
              print
            }
          ' "$DIR/checks/$file"
        else
          awk '
            /^[[:space:]]*hdr "/ {
              sub(/^[[:space:]]*hdr "/, "")
              sub(/"$/, "")
              print
            }
          ' "$DIR/checks/$file"
        fi
        ;;
    esac
  done < "$REAL"
}

expected='Symlinks
Homebrew (Brewfile)
MDM / company apps
macOS defaults
Dock
Desktop assignments (Dock → Options → Assign To)
Login shell
Hostname
Display auto-brightness
Display (More Space)
ARZOPA display
Wallpaper
Desktop widgets
User picture
Power (sleep and wake)
URL handlers
File handlers
Folders
Unwanted apps
Dictation shortcut
Quick Note shortcut
Spotlight shortcut
Finder icon view defaults
Karabiner Fn-kill
Karabiner background
Hammerspoon
Login Items (banned open-at-login)
Finder sidebar Recents
Finder Favorites
Finder sidebar rows
Show Finder shortcut
CotEditor
Ghostty config
Logi Options+
Modes (Hammerspoon)
Notifications
Leftover app backups
Security hygiene
Mac health
Manual steps (lib/manual-steps.list)'

eq "section headings and order match the pre-split report" "$expected" "$(headings_in_source)"

for f in "$DIR"/checks/*.sh; do
  base="$(basename "$f")"
  has "runner sources $base" "checks/$base" "$(cat "$REAL")"
done
# shellcheck disable=SC2016  # the needle is a source line, compared as text
eq "finder is sourced twice" 2 "$(grep -c '\. "\$DOTDIR/checks/finder.sh"' "$REAL")"

# --only runs the named areas in the usual order.
run_only() {
  local rc=0 out
  out="$("$REAL" --no-color "$@" 2>&1)" || rc=$?
  printf '%s\n' "$rc"
  printf '%s\n' "$out" | awk 'NF && $0 !~ /^[[:space:]]/ && $0 != "Summary" { print }'
}

only_out="$(run_only --only coteditor,hostname)"
eq "--only coteditor,hostname headings" "Hostname
CotEditor" "$(printf '%s\n' "$only_out" | tail -n +2)"

only_out="$(run_only --only hostname,coteditor)"
eq "--only hostname,coteditor is still the usual order" "Hostname
CotEditor" "$(printf '%s\n' "$only_out" | tail -n +2)"

only_out="$(run_only --only=hostname)"
eq "--only=hostname heading" "Hostname" "$(printf '%s\n' "$only_out" | tail -n +2)"

bad_rc=0
bad_out="$("$REAL" --only nosuch 2>&1)" || bad_rc=$?
eq "unknown area exits 2" 2 "$bad_rc"
has "unknown area names it" "Unknown area: nosuch" "$bad_out"

empty_rc=0
empty_out="$("$REAL" --only 2>&1)" || empty_rc=$?
eq "--only without a list exits 2" 2 "$empty_rc"
has "--only without a list explains itself" "--only needs" "$empty_out"

dry_rc=0
dry_out="$("$REAL" --only hostname --dry-run 2>&1)" || dry_rc=$?
eq "--only --dry-run without --fix exits 2" 2 "$dry_rc"
has "dry-run without --fix explains itself" "--dry-run only applies" "$dry_out"

help_rc=0
help_out="$("$REAL" --help 2>&1)" || help_rc=$?
ok "--help exits 0" "$help_rc"
has "help mentions --only" "--only AREA" "$help_out"
has "help lists symlinks" "symlinks" "$help_out"
has "help lists finder" "finder" "$help_out"

shim_out="$("$SHIM" --no-color --only hostname 2>&1)" || shim_rc=$?
real_out="$("$REAL" --no-color --only hostname 2>&1)" || real_rc=$?
eq "check.sh --only matches macconfig-check.sh" "${real_rc:-0}
$real_out" "${shim_rc:-0}
$shim_out"

# The new warn-only checks are not wired to a SAFE fixer.
for id in broken-symlink hammerspoon-config launchagent-template security software-update; do
  row="$(awk -F'|' -v id="$id" '$1 == id { print $2 "|" $3; exit }' "$DIR/lib/autofix.list")"
  eq "$id is report-only" "PAUL|" "$row"
done

printf 'sections tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
