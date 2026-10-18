#!/usr/bin/env bash
#
# Unit tests for lib/notification-prefs.py. Synthetic plists only — the
# usernoted store is never opened or written. Run: ./tests/notification-prefs.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$DIR/lib/notification-prefs.py"
OFF="$DIR/lib/notifications-off.list"
REVIEWED="$DIR/lib/notifications-reviewed.list"
CHECK="$DIR/macconfig-check.sh"
STEPS="$DIR/lib/manual-steps.list"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "notification-prefs tests: python3 not found, skipped"; exit 0; fi

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

# write_plist PATH EXPR [xml|binary]
write_plist() {
  "$PY" - "$1" "$2" "${3:-xml}" <<'PY'
import plistlib, sys
path, expr, kind = sys.argv[1], sys.argv[2], sys.argv[3]
p = eval(expr)
fmt = plistlib.FMT_BINARY if kind == "binary" else plistlib.FMT_XML
with open(path, "wb") as fh:
    plistlib.dump(p, fh, fmt=fmt)
PY
}
run() { "$PY" "$HELPER" --plist "$1" --off "${2:-$OFF}" --reviewed "${3:-$REVIEWED}"; }

# Real Off-list names, in order, must stay the manual-step title.
off_names="$(grep -E '^[^#[:space:]]' "$OFF" | sed -E 's/^[^#]*#[[:space:]]*//; s/[[:space:]]+$//')"
title="$(awk -F'|' '$1 == "notifications-apps" { print $3; exit }' "$STEPS")"
title_names="$(printf '%s\n' "$title" | sed -E 's/^Turn notifications Off for //')"
off_joined="$(printf '%s\n' "$off_names" | awk 'NR > 1 { printf ", " } { printf "%s", $0 } END { printf "\n" }')"
eq "off-list names match the manual step" "$off_joined" "$title_names"
eq "notifications-apps is checked by macconfig-check.sh" "@macconfig-check.sh" \
  "$(awk -F'|' '$1 == "notifications-apps" { print $6; exit }' "$STEPS")"

eq "allow bit constant is 25" "ALLOW_NOTIFICATIONS_BIT = 25" \
  "$(grep -E '^ALLOW_NOTIFICATIONS_BIT = ' "$HELPER")"
has "helper default plist is the usernoted group store" \
  'group.com.apple.usernoted.plist' "$(cat "$HELPER")"
miss "helper does not read the old ncprefs path as its store" \
  'com.apple.ncprefs.plist"' "$(cat "$HELPER")"
writers="$(grep -nE 'defaults write|PlistBuddy|killall usernoted|plistlib.dump|subprocess' \
  "$CHECK" "$HELPER" || true)"
eq "check and helper never write the notification store" "" "$writers"

# Sample flags from this Mac (macOS 27). Bit 25 is clear on every Off-list app
# and set on Chrome. Plist order is deliberately not the Off-list order.
SAMPLE='{
  "apps": [
    {"bundle-id": "com.google.Chrome", "flags": 41951246, "path": "/Applications/Google Chrome.app"},
    {"bundle-id": "com.apple.Safari", "flags": 33554432},
    {"bundle-id": "_SYSTEM_CENTER_banner", "flags": 33554432},
    {"bundle-id": "com.apple.Passbook", "flags": 814219270},
    {"bundle-id": "com.apple.tips", "flags": 294125584},
    {"bundle-id": "com.spotify.client", "flags": 276832270},
    {"bundle-id": "com.tinyspeck.slackmacgap", "flags": 276832270},
    {"bundle-id": "com.microsoft.teams2", "flags": 276832270},
    {"bundle-id": "com.apple.mail", "flags": 276824078},
    {"bundle-id": "com.apple.Home", "flags": 830996486},
    {"bundle-id": "com.apple.gamecenter", "flags": 5109194758},
    {"bundle-id": "com.apple.FaceTime", "flags": 278929416},
    {"bundle-id": "co.anysphere.cursor.nightly", "flags": 276832270},
    {"bundle-id": "com.apple.iCal", "flags": 814219286},
    {"bundle-id": "org.hammerspoon.Hammerspoon", "flags": 8396822},
    {"bundle-id": "com.example.newapp", "flags": 1},
  ]
}'
write_plist "$tmp/sample.plist" "$SAMPLE"
out="$(run "$tmp/sample.plist")"; rc=$?
eq "sample exits 0" 0 "$rc"
eq "sample snapshot" "$(cat <<'EOF'
ok|com.apple.iCal|Calendar (com.apple.iCal): Allow Notifications is off (flags=814219286)
ok|co.anysphere.cursor.nightly|Cursor Nightly (co.anysphere.cursor.nightly): Allow Notifications is off (flags=276832270)
ok|com.apple.FaceTime|FaceTime (com.apple.FaceTime): Allow Notifications is off (flags=278929416)
ok|com.apple.gamecenter|Game Center (com.apple.gamecenter): Allow Notifications is off (flags=5109194758)
ok|com.apple.Home|Home (com.apple.Home): Allow Notifications is off (flags=830996486)
ok|com.apple.mail|Mail (com.apple.mail): Allow Notifications is off (flags=276824078)
ok|com.microsoft.teams2|Microsoft Teams (com.microsoft.teams2): Allow Notifications is off (flags=276832270)
ok|com.tinyspeck.slackmacgap|Slack (com.tinyspeck.slackmacgap): Allow Notifications is off (flags=276832270)
ok|com.spotify.client|Spotify (com.spotify.client): Allow Notifications is off (flags=276832270)
ok|com.apple.tips|Tips (com.apple.tips): Allow Notifications is off (flags=294125584)
ok|com.apple.Passbook|Wallet (com.apple.Passbook): Allow Notifications is off (flags=814219270)
info|com.example.newapp|com.example.newapp: third-party app is not in lib/notifications-reviewed.list or lib/notifications-off.list (Allow Notifications is off (flags=1)) — review it in System Settings → Notifications, then add the bundle id to one of those lists
EOF
)" "$out"

# Chrome is the positive control: bit 25 set, reviewed, so no warn and no info.
miss "reviewed Chrome is not a warning" "com.google.Chrome" "$out"
miss "Apple apps outside the Off list are ignored" "com.apple.Safari" "$out"
miss "system-center apps are ignored" "_SYSTEM_CENTER_" "$out"

# Slack with bit 25 set is the drift the check exists to catch.
SLACK_ON='{
  "apps": [
    {"bundle-id": "com.tinyspeck.slackmacgap", "flags": 310386702},
    {"bundle-id": "com.apple.iCal", "flags": 814219286},
  ]
}'
printf 'com.apple.iCal # Calendar\ncom.tinyspeck.slackmacgap # Slack\n' > "$tmp/off.list"
printf 'com.google.Chrome # Chrome\n' > "$tmp/reviewed.list"
write_plist "$tmp/slack-on.plist" "$SLACK_ON"
out="$(run "$tmp/slack-on.plist" "$tmp/off.list" "$tmp/reviewed.list")"
eq "bit 25 set is a warning" \
  "ok|com.apple.iCal|Calendar (com.apple.iCal): Allow Notifications is off (flags=814219286)
warn|com.tinyspeck.slackmacgap|Slack (com.tinyspeck.slackmacgap): Allow Notifications is on (flags=310386702, bit 25 set) — System Settings → Notifications → turn it off. macconfig-check.sh --fix does not change this" \
  "$out"

# Any copy with the bit set counts, even if another copy is clear.
write_plist "$tmp/dup.plist" '{
  "apps": [
    {"bundle-id": "com.tinyspeck.slackmacgap", "flags": 276832270},
    {"bundle-id": "com.tinyspeck.slackmacgap", "flags": 310386702},
  ]
}'
out="$(run "$tmp/dup.plist" "$tmp/off.list" "$tmp/reviewed.list")"
has "duplicate with the bit set warns" "flags=276832270/310386702, bit 25 set" "$out"
has "duplicate status is warn" "warn|com.tinyspeck.slackmacgap|" "$out"

write_plist "$tmp/missing-app.plist" '{"apps": [{"bundle-id": "com.apple.iCal", "flags": 814219286}]}'
out="$(run "$tmp/missing-app.plist" "$tmp/off.list" "$tmp/reviewed.list")"
has "listed app absent from the store warns" \
  "warn|com.tinyspeck.slackmacgap|Slack (com.tinyspeck.slackmacgap): not in the notification store — can't confirm Allow Notifications is off" \
  "$out"

write_plist "$tmp/bad-flags.plist" '{"apps": [{"bundle-id": "com.apple.iCal", "flags": "814219286"}]}'
out="$(run "$tmp/bad-flags.plist" "$tmp/off.list" "$tmp/reviewed.list")"
has "non-integer flags warn" "flags unreadable (?)" "$out"

write_plist "$tmp/only-bit.plist" '{"apps": [{"bundle-id": "com.apple.iCal", "flags": 33554432}]}'
out="$(run "$tmp/only-bit.plist" "$tmp/off.list" "$tmp/reviewed.list")"
has "the bit alone means allowed" "bit 25 set" "$out"

write_plist "$tmp/zero.plist" '{"apps": [{"bundle-id": "com.apple.iCal", "flags": 0}]}'
out="$(run "$tmp/zero.plist" "$tmp/off.list" "$tmp/reviewed.list")"
has "zero flags means off" "ok|com.apple.iCal|Calendar (com.apple.iCal): Allow Notifications is off (flags=0)" "$out"

write_plist "$tmp/binary.plist" "$SLACK_ON" binary
eq "binary plist matches xml" "$(run "$tmp/slack-on.plist" "$tmp/off.list" "$tmp/reviewed.list")" \
  "$(run "$tmp/binary.plist" "$tmp/off.list" "$tmp/reviewed.list")"

before="$("$PY" -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$tmp/binary.plist")"
run "$tmp/binary.plist" "$tmp/off.list" "$tmp/reviewed.list" >/dev/null
after="$("$PY" -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$tmp/binary.plist")"
eq "reading does not modify the plist" "$before" "$after"

out="$(run "$tmp/no-such-store.plist" "$tmp/off.list" "$tmp/reviewed.list")"; rc=$?
eq "missing store exits 0" 0 "$rc"
has "missing store is an error line" "error|-|notification store missing at $tmp/no-such-store.plist" "$out"

printf 'not a plist\n' > "$tmp/garbage.plist"
out="$(run "$tmp/garbage.plist" "$tmp/off.list" "$tmp/reviewed.list")"; rc=$?
eq "garbage exits 0" 0 "$rc"
has "garbage is an error line" "error|-|could not read the notification store" "$out"

write_plist "$tmp/no-apps.plist" '{"version": 1, "dnd_prefs": {}}'
out="$(run "$tmp/no-apps.plist" "$tmp/off.list" "$tmp/reviewed.list")"; rc=$?
eq "missing apps array exits 0" 0 "$rc"
eq "missing apps array is one error" "error|-|notification store has no apps array" "$out"

printf '# just a comment\n\nnot a bundle id!!\n' > "$tmp/bad-off.list"
out="$(run "$tmp/sample.plist" "$tmp/bad-off.list" "$tmp/reviewed.list")"; rc=$?
eq "bad off list exits 0" 0 "$rc"
has "bad off list is an error line" "error|-|could not read notification lists" "$out"

printf 'com.apple.iCal # Calendar\ncom.apple.iCal # again\n' > "$tmp/dup-off.list"
out="$(run "$tmp/sample.plist" "$tmp/dup-off.list" "$tmp/reviewed.list")"
has "duplicate off-list id is an error" "duplicate bundle id com.apple.iCal" "$out"

# The macconfig-check.sh section reports helper warnings as warnings (Needs Paul
# via the PAUL row), and unknown apps as info. It has no writer.
section="$(awk '/^# ---- 13e\. Notifications/,/^# ---- 14\. Leftover/' "$CHECK")"
has "section calls the helper" 'lib/notification-prefs.py' "$section"
# shellcheck disable=SC2016  # needles are source text, compared literally
has "section warns" 'warn "$n_msg"' "$section"
# shellcheck disable=SC2016
has "section info" 'info "$n_msg"' "$section"
has "section tags notifications" 'fixid notifications' "$section"
miss "section does not report DRIFT" 'bad ' "$section"
eq "notifications is Needs Paul" "PAUL|" \
  "$(awk -F'|' '$1 == "notifications" { print $2 "|" $3; exit }' "$DIR/lib/autofix.list")"

printf 'notification-prefs tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
