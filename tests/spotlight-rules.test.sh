#!/usr/bin/env bash
#
# Spotlight Results from Apps: the 15 names in lib/spotlight-apps.list.
# The check does not read the toggles. EnabledPreferenceRules is the row
# list, and a row stays after the toggle is turned off, so that old reading
# is check by hand rather than a warning. Nothing is written.
# Run: ./tests/spotlight-rules.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$DIR/lib/spotlight-rules.py"
LIST="$DIR/lib/spotlight-apps.list"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "spotlight-rules tests: python3 not found, skipped"; exit 0; fi

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

OFF="Books, Calendar, Contacts, Mail, Messages, Music, Notes, Photos, Podcasts, Reminders, Safari, Shortcuts, Stocks, Tips, and Voice Memos"
ON="App Store, Calculator, Dictionary, and System Settings"

names="$(awk -F'|' '$1 !~ /^#/ && NF { print $1 }' "$LIST" | tr '\n' ',' | sed 's/,$//')"
eq "fifteen apps" "Books,Calendar,Contacts,Mail,Messages,Music,Notes,Photos,Podcasts,Reminders,Safari,Shortcuts,Stocks,Tips,Voice Memos" "$names"
miss "Keynote is not required off" "Keynote" "$names"
miss "Numbers is not required off" "Numbers" "$names"
eq "Calendar bundle" "com.apple.iCal" "$(awk -F'|' '$1=="Calendar" { print $2; exit }' "$LIST")"
eq "Contacts bundle" "com.apple.AddressBook" "$(awk -F'|' '$1=="Contacts" { print $2; exit }' "$LIST")"
eq "Messages bundle" "com.apple.MobileSMS" "$(awk -F'|' '$1=="Messages" { print $2; exit }' "$LIST")"
eq "Music bundle" "com.apple.Music" "$(awk -F'|' '$1=="Music" { print $2; exit }' "$LIST")"
miss "App Store is not required off" "App Store" "$names"
miss "Calculator is not required off" "Calculator" "$names"
miss "Dictionary is not required off" "Dictionary" "$names"
miss "System Settings is not required off" "System Settings" "$names"

run() { "$PY" "$HELPER" --list "$LIST" --json "$1"; }

out="$(run '["com.apple.mail","com.apple.iCal","com.apple.AddressBook","com.apple.MobileSMS","com.apple.Music","com.apple.Safari"]')"
eq "a row list is check by hand" "hand" "${out%%|*}"
miss "a row list is not reported as on" "are on" "$out"
has "hand message names Calendar" "Calendar" "$out"
has "hand message names the apps that stay on" "$ON" "$out"

out="$("$PY" "$HELPER" --list "$LIST")"
eq "no preference is check by hand" "hand" "${out%%|*}"
has "hand message names the apps that should be off" "$OFF" "$out"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
"$PY" - "$tmp" <<'PY'
import plistlib, sys
plistlib.dump({"EnabledPreferenceRules": ["com.apple.mail", "com.apple.Safari"]}, open(sys.argv[1], "wb"))
PY
out="$("$PY" "$HELPER" --list "$LIST" --plist "$tmp")"
eq "exported row list is check by hand" "hand" "${out%%|*}"
miss "exported row list is not reported as on" "are on" "$out"

empty="$(mktemp)"
printf '%s\n' '# nothing' > "$empty"
out="$("$PY" "$HELPER" --list "$empty")"
eq "an empty app list warns" "warn" "${out%%|*}"
rm -f "$empty"

title="$(awk -F'|' '$1=="spotlight-results" { print $3; exit }' "$DIR/lib/manual-steps.list")"
has "manual step names the apps that should be off" "$OFF" "$title"
has "manual step names the apps that stay on" "$ON" "$title"
has "manual step says to check by hand" "by hand" "$title"
eq "manual step uses the spotlight check" "spotlight-results" \
  "$(awk -F'|' '$1=="spotlight-results" { print $6; exit }' "$DIR/lib/manual-steps.list")"

readme="$(cat "$DIR/docs/manual-steps.md")"
has "Manual-steps doc names the apps that should be off" "$OFF" "$readme"
has "Manual-steps doc names the apps that stay on" "$ON" "$readme"
has "Manual-steps doc says the step is checked by hand" "checked by hand" "$readme"

miss "the check does not export Spotlight preferences" "defaults export com.apple.Spotlight" \
  "$(cat "$DIR/lib/session-checks.sh")"

printf 'spotlight-rules tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
