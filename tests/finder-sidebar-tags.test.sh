#!/usr/bin/env bash
#
# Finder sidebar tags. FavoriteTagNames empty means every "Show these tags
# in the sidebar" box is unticked. The helper only reads. Run:
# ./tests/finder-sidebar-tags.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$DIR/lib/finder-sidebar-tags.py"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "finder-sidebar-tags tests: python3 not found, skipped"; exit 0; fi

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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
chmod +x "$HELPER"

write_plist() {
  "$PY" - "$tmp/finder.plist" "$1" <<'PY'
import plistlib, sys
path, kind = sys.argv[1], sys.argv[2]
if kind == "empty":
    data = {"FavoriteTagNames": []}
elif kind == "empty-recent-off":
    data = {"FavoriteTagNames": [], "ShowRecentTags": False}
elif kind == "empty-recent-on":
    data = {"FavoriteTagNames": [], "ShowRecentTags": True}
elif kind == "named":
    data = {"FavoriteTagNames": ["Red", "Work", "Important"]}
elif kind == "both":
    data = {"FavoriteTagNames": ["Red"], "ShowRecentTags": True}
elif kind == "missing-key":
    data = {"ShowHardDrivesOnDesktop": False}
elif kind == "bad-type":
    data = {"FavoriteTagNames": "Red"}
elif kind == "bad-recent":
    data = {"FavoriteTagNames": [], "ShowRecentTags": "yes"}
else:
    raise SystemExit("unknown " + kind)
plistlib.dump(data, open(path, "wb"))
PY
}

run() { "$PY" "$HELPER" --plist "$tmp/finder.plist"; }

write_plist empty
out="$(run)"
eq "an empty tag list passes" "ok" "${out%%|*}"
has "an empty tag list says none are shown" "No tags are shown" "$out"

write_plist empty-recent-off
out="$(run)"
eq "recent tags off still passes" "ok" "${out%%|*}"

write_plist empty-recent-on
out="$(run)"
eq "recent tags on warns" "warn" "${out%%|*}"
has "recent tags on names the key" "ShowRecentTags is on" "$out"
has "recent tags says the named boxes do not turn them off" \
  "does not turn recent tags off" "$out"
has "recent tags names the Sidebar row" "hide Recent Tags" "$out"
miss "recent tags are not fixed by unticking the named boxes again" \
  "untick every box" "$out"

write_plist named
out="$(run)"
eq "listed tags warn" "warn" "${out%%|*}"
has "listed tags names Red" "Red" "$out"
has "listed tags names Work" "Work" "$out"
has "listed tags names Important" "Important" "$out"
has "listed tags says to untick them" "untick every box" "$out"
miss "listed tags do not mention recent tags" "recent tags" "$out"

write_plist both
out="$(run)"
eq "listed tags and recent tags both warn" "warn" "${out%%|*}"
has "both warnings still say to untick the boxes" "untick every box" "$out"
has "both warnings say the boxes do not turn recent tags off" \
  "does not turn recent tags off" "$out"

write_plist missing-key
out="$(run)"
eq "a missing FavoriteTagNames warns" "warn" "${out%%|*}"
has "a missing key names FavoriteTagNames" "FavoriteTagNames is not set" "$out"
miss "a missing ShowRecentTags is not itself a failure" "ShowRecentTags is on" "$out"

write_plist bad-type
out="$(run)"
eq "a non-list stays by hand" "info" "${out%%|*}"
has "a non-list names the click path" "Show these tags in the sidebar" "$out"

write_plist bad-recent
out="$(run)"
eq "a non-boolean ShowRecentTags stays by hand" "info" "${out%%|*}"

before="$(cksum "$tmp/finder.plist")"
run >/dev/null
eq "a read does not rewrite the plist" "$before" "$(cksum "$tmp/finder.plist")"

printf 'not a plist\n' > "$tmp/finder.plist"
out="$(run)"
eq "a broken plist stays by hand" "info" "${out%%|*}"
has "a broken plist stays by hand in words" "could not be read" "$out"

writers="$(grep -nE 'open\(.*["'\'']wb["'\'']|plistlib.dump' "$HELPER" || true)"
eq "helper does not write a preference" "" "$writers"
miss "helper does not call defaults write" "defaults write" "$(cat "$HELPER")"

has "manual step says no tags are shown" "No tags are shown in the sidebar, including recent tags." \
  "$(awk -F'|' '$1=="finder-sidebar" { print $3; exit }' "$DIR/lib/manual-steps.list")"
has "manual step names the Tags pane" "Finder → Settings → Tags" \
  "$(awk -F'|' '$1=="finder-sidebar" { print $4; exit }' "$DIR/lib/manual-steps.list")"
has "manual step says the tag boxes do not turn recent tags off" \
  "do not turn recent tags off" \
  "$(awk -F'|' '$1=="finder-sidebar" { print $4; exit }' "$DIR/lib/manual-steps.list")"
has "manual step names Recent Tags" "hide Recent Tags" \
  "$(awk -F'|' '$1=="finder-sidebar" { print $4; exit }' "$DIR/lib/manual-steps.list")"
miss "manual step no longer says Shared is first" "first visible" \
  "$(awk -F'|' '$1=="finder-sidebar" { print; exit }' "$DIR/lib/manual-steps.list")"
eq "shared row is hidden" "hidden" \
  "$(awk -F'|' '$1=="shared" { print $3; exit }' "$DIR/lib/finder-sidebar-rows.list")"
has "favorites list still includes Developer" "Developer|@HOME@/Developer" \
  "$(cat "$DIR/lib/sidebar-favorites.list")"

printf 'finder-sidebar-tags tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
