#!/usr/bin/env bash
#
# A step with a check uses that result. Ok is skipped. Not ok says
# "Not set yet:" and the reason. Only a step with no check says
# "Can't check this automatically". A check that covers part of a step
# names that part. manualsteps and the macconfig step function agree.
# Run: ./tests/why-shown.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MS="$DIR/scripts/manual-steps.sh"
LIST="$DIR/lib/manual-steps.list"
PY="$(command -v python3 || true)"

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
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;;
    *) pass=$((pass + 1)) ;; esac
}

CANT="Can't check this automatically"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export NO_COLOR=1

# Titles no longer repeat the why-line.
titles="$(awk -F'|' '$1 !~ /^[[:space:]]*#/ && NF { print $3 }' "$LIST")"
miss "no title says macconfig checks this" "macconfig checks this" "$titles"
miss "no title says Check by hand:" "Check by hand:" "$titles"
miss "no title says Check this page by hand" "Check this page by hand" "$titles"
miss "no title says macconfig checks the selected layout" "macconfig checks the selected layout" "$titles"

# Every shown step that has a check id. Ok steps are not on this list.
pending="$(NO_COLOR=1 "$MS" pending 2>"$tmp/pending.err")"
eq "pending on the real list exits 0" 0 "$?"
# number -> check field, in list order.
awk -F'|' '$1 !~ /^[[:space:]]*#/ && $1 !~ /^[[:space:]]*$/ { n++; print n "|" $1 "|" $6 }' "$LIST" > "$tmp/ids.txt"
bad="$(printf '%s\n' "$pending" | awk -v cant="$CANT" '
  FNR == NR { check[$1] = $3; next }
  /^[0-9]+\. / {
    num = $0
    sub(/\..*/, "", num)
    gsub(/^ +/, "", num)
    getline why
    gsub(/^ +/, "", why)
    if (check[num] != "" && index(why, cant) > 0) print num " " check[num] " " why
  }
' "$tmp/ids.txt" -)"
eq "no step with a check id is labelled can't-check" "" "$bad"

# British layout: missing key is not set yet, and macconfig reports the same warn.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/defaults" <<'EOF'
#!/bin/sh
exit 1
EOF
cat > "$tmp/bin/open" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$tmp/bin/defaults" "$tmp/bin/open"
printf '%s\n' \
  'input-british|Display, keyboard & desktop|Keyboard input source: British|System Settings → Keyboard|x-apple.systempreferences:com.apple.Keyboard-Settings.extension|input-british' \
  > "$tmp/british.list"
brit="$(PATH="$tmp/bin:$PATH" MANUAL_STEPS_LIST="$tmp/british.list" "$MS" check --porcelain 2>"$tmp/brit.err")"
eq "missing British layout warns" "warn" "$(printf '%s\n' "$brit" | cut -d'|' -f1)"
has "missing British layout names the reason" "no British keyboard layout is selected" "$brit"
brit_open="$(printf 's\n' | PATH="$tmp/bin:$PATH" NO_COLOR=1 MANUAL_STEPS_OPEN_TTY=1 \
  MANUAL_STEPS_LIST="$tmp/british.list" "$MS" open 2>"$tmp/britopen.err")"
has "open says the British layout is not set yet" \
  "Not set yet: no British keyboard layout is selected" "$brit_open"
miss "open does not say the British layout can't be checked" "$CANT" "$brit_open"
mac="$(PATH="$tmp/bin:$PATH" NO_COLOR=1 MANUAL_STEPS_LIST="$tmp/british.list" \
  "$DIR/macconfig-check.sh" --only manual --no-color 2>"$tmp/britmac.err")" || true
has "macconfig warns on the British layout" "no British keyboard layout is selected" "$mac"
miss "macconfig does not leave the British layout as check by hand" "check by hand" \
  "$(printf '%s\n' "$mac" | grep -F 'Keyboard input source' || true)"

# Per-app notifications. Off (or not registered yet) is done, even when some
# other app is only an info line. On is not set yet. The section function and
# manualsteps use the same words.
if [ -n "$PY" ]; then
  notif_home="$tmp/notif-home"
  notif_dir="$notif_home/Library/Group Containers/group.com.apple.usernoted/Library/Preferences"
  mkdir -p "$notif_dir" "$tmp/bin"
  printf '%s\n' \
    'notifications-apps|Notifications|Turn notifications off|System Settings → Notifications|x-apple.systempreferences:com.apple.Notifications-Settings.extension|@macconfig:notifications' \
    > "$tmp/notif.list"
  write_notif() {
    "$PY" - "$notif_dir/group.com.apple.usernoted.plist" "$1" <<'PY'
import plistlib, sys
path, flags = sys.argv[1], int(sys.argv[2])
plistlib.dump({"apps": [
    {"bundle-id": "com.apple.iCal", "flags": flags},
    {"bundle-id": "com.example.newapp", "flags": 1},
]}, open(path, "wb"))
PY
  }
  write_notif 814219286
  off_porc="$(HOME="$notif_home" MANUAL_STEPS_LIST="$tmp/notif.list" "$MS" check --porcelain 2>"$tmp/off.err")"
  eq "notifications that are off pass" "ok" "$(printf '%s\n' "$off_porc" | cut -d'|' -f1)"
  off_open="$(printf 's\n' | HOME="$notif_home" PATH="$tmp/bin:$PATH" NO_COLOR=1 \
    MANUAL_STEPS_OPEN_TTY=1 MANUAL_STEPS_LIST="$tmp/notif.list" "$MS" open 2>"$tmp/offopen.err")"
  miss "open skips notifications that are already off" "Turn notifications off" "$off_open"
  miss "an off notification list is not labelled can't-check" "$CANT" "$off_open"

  write_notif 33554432
  on_porc="$(HOME="$notif_home" MANUAL_STEPS_LIST="$tmp/notif.list" "$MS" check --porcelain 2>"$tmp/on.err")"
  eq "a notification that is on warns" "warn" "$(printf '%s\n' "$on_porc" | cut -d'|' -f1)"
  has "the warn names Calendar" "Calendar" "$on_porc"
  has "the warn names Allow Notifications" "Allow Notifications is on" "$on_porc"
  on_open="$(printf 's\n' | HOME="$notif_home" PATH="$tmp/bin:$PATH" NO_COLOR=1 \
    MANUAL_STEPS_OPEN_TTY=1 MANUAL_STEPS_LIST="$tmp/notif.list" "$MS" open 2>"$tmp/onopen.err")"
  has "open says notifications are not set yet" "Not set yet:" "$on_open"
  has "open names Calendar" "Calendar" "$on_open"
  miss "an on notification is not labelled can't-check" "$CANT" "$on_open"

  # shellcheck source=../lib/covered-steps.sh disable=SC1091
  DOTDIR="$DIR"
  with_timeout() { shift; "$@"; }
  . "$DIR/lib/covered-steps.sh"
  direct="$(HOME="$notif_home" DOT_PYTHON="$PY" covered_step_run notifications-apps notifications)"
  eq "manualsteps and the notification check agree" \
    "$(printf '%s\n' "$on_porc" | cut -d'|' -f5-)" \
    "$(printf '%s\n' "$direct" | cut -d'|' -f2-)"
fi

# A step with no check still uses the can't-check line.
printf '%s\n' 'plain|Group|Do this by hand|Somewhere||' > "$tmp/plain.list"
plain="$(MANUAL_STEPS_LIST="$tmp/plain.list" "$MS" pending 2>"$tmp/plain.err")"
has "a step with no check says it can't be checked" "$CANT" "$plain"

printf 'why-shown tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
