#!/usr/bin/env bash
#
# Placed desktop widgets. Synthetic plists only — the notificationcenterui
# plist is not written. 0 instances is ok, 3 is a warning, unreadable is
# check by hand. Run: ./tests/desktop-widgets.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$DIR/lib/desktop-widgets.py"
MS="$DIR/scripts/manual-steps.sh"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "desktop-widgets tests: python3 not found, skipped"; exit 0; fi

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

status_of() { printf '%s' "${1%%|*}"; }
msg_of() {
  local rest="${1#*|}"
  printf '%s' "${rest#*|}"
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

"$PY" - "$tmp" <<'PY'
import os
import plistlib
import sys

out = sys.argv[1]

def dump(name, obj):
    with open(os.path.join(out, name), "wb") as fh:
        plistlib.dump(obj, fh, fmt=plistlib.FMT_BINARY)

def blob(obj):
    return plistlib.dumps(obj, fmt=plistlib.FMT_BINARY)

weather = blob({"extension": "com.apple.weather.widget"})
calendar = blob({
    "$version": 100000,
    "$archiver": "NSKeyedArchiver",
    "$top": {"root": plistlib.UID(1)},
    "$objects": [
        "$null",
        {
            "$class": plistlib.UID(4),
            "NS.keys": [plistlib.UID(2)],
            "NS.objects": [plistlib.UID(3)],
        },
        "kind",
        "com.apple.mobilecal.CalendarWidgetExtension",
        {"$classname": "NSDictionary", "$classes": ["NSDictionary", "NSObject"]},
    ],
})
photos = blob({
    "$version": 100000,
    "$archiver": "NSKeyedArchiver",
    "$top": {"root": plistlib.UID(1)},
    "$objects": [
        "$null",
        {"extension": plistlib.UID(2)},
        "com.apple.Photos.PhotosWidget",
    ],
})
placement = blob({"placed": True})
dump("three.plist", {
    "widgets": {"instances": [weather, calendar, photos]},
    "DesktopWidgetPlacementStorage": placement,
})
dump("three-one-unnamed.plist", {
    "widgets": {"instances": [weather, calendar, b"not-a-plist"]},
})
dump("zero.plist", {
    "widgets": {"instances": []},
    "DesktopWidgetPlacementStorage": placement,
})
dump("no-instances-key.plist", {
    "widgets": {"other": 1},
    "DesktopWidgetPlacementStorage": placement,
})
dump("no-widgets-key.plist", {"DesktopWidgetPlacementStorage": placement})
dump("bad-widgets.plist", {"widgets": ["nope"]})
dump("bad-instances.plist", {"widgets": {"instances": {"not": "a list"}}})
dump("one-unnamed.plist", {"widgets": {"instances": [b"not-a-plist"]}})
dump("one-named.plist", {"widgets": {"instances": [weather]}})
with open(os.path.join(out, "garbage.plist"), "wb") as fh:
    fh.write(b"this is not a plist")
with open(os.path.join(out, "empty.plist"), "wb") as fh:
    fh.write(b"")
os.makedirs(os.path.join(out, "adir"))
PY

run() { "$PY" "$HELPER" --plist "$1"; }

out="$(run "$tmp/three.plist")"
eq "3 instances warns" warn "$(status_of "$out")"
eq "3 instances names the count and each kind" \
  "3 widgets on the desktop: com.apple.weather.widget, com.apple.mobilecal.CalendarWidgetExtension, com.apple.Photos.PhotosWidget" \
  "$(msg_of "$out")"

before="$(cksum "$tmp/three.plist")"
run "$tmp/three.plist" >/dev/null
eq "reading 3 instances does not rewrite the plist" "$before" "$(cksum "$tmp/three.plist")"

out="$(run "$tmp/three-one-unnamed.plist")"
eq "an unnamed blob still warns" warn "$(status_of "$out")"
eq "an unnamed blob keeps the count and does not fail the check" \
  "3 widgets on the desktop: com.apple.weather.widget, com.apple.mobilecal.CalendarWidgetExtension, and 1 more" \
  "$(msg_of "$out")"

out="$(run "$tmp/one-unnamed.plist")"
eq "one unnamed widget warns" warn "$(status_of "$out")"
eq "one unnamed widget has no kind suffix" "1 widget on the desktop" "$(msg_of "$out")"

out="$(run "$tmp/one-named.plist")"
eq "one named widget is singular" "1 widget on the desktop: com.apple.weather.widget" "$(msg_of "$out")"

for fixture in zero.plist no-instances-key.plist no-widgets-key.plist; do
  out="$(run "$tmp/$fixture")"
  eq "$fixture is ok" ok "$(status_of "$out")"
  eq "$fixture says there are no widgets" "no widgets on the desktop" "$(msg_of "$out")"
done

out="$(run "$tmp/missing.plist")"
eq "a missing plist is ok" ok "$(status_of "$out")"
eq "a missing plist says there are no widgets" "no widgets on the desktop" "$(msg_of "$out")"
if [ -e "$tmp/missing.plist" ]; then
  miss "a missing plist is not created" "present" "present"
else
  eq "a missing plist is not created" "absent" "absent"
fi

for fixture in garbage.plist empty.plist bad-widgets.plist bad-instances.plist; do
  out="$(run "$tmp/$fixture")"
  eq "$fixture is check by hand" hand "$(status_of "$out")"
  has "$fixture says check by hand" "check by hand" "$out"
  miss "$fixture is not a warning" "warn|" "$out"
done

out="$(run "$tmp/adir")"
eq "a directory is check by hand" hand "$(status_of "$out")"
has "a directory says check by hand" "check by hand" "$out"

# Default path, not only --plist. Placement storage must not count as widgets.
home="$tmp/home"
plist_rel="Library/Containers/com.apple.notificationcenterui/Data/Library/Preferences"
mkdir -p "$home/$plist_rel"
cp "$tmp/zero.plist" "$home/$plist_rel/com.apple.notificationcenterui.plist"
out="$(env -u DESKTOP_WIDGETS_PLIST HOME="$home" "$PY" "$HELPER")"
eq "default path with 0 instances is ok" ok "$(status_of "$out")"
cp "$tmp/three.plist" "$home/$plist_rel/com.apple.notificationcenterui.plist"
out="$(env -u DESKTOP_WIDGETS_PLIST HOME="$home" "$PY" "$HELPER")"
eq "default path with 3 instances warns" warn "$(status_of "$out")"
has "default path names Weather" "com.apple.weather.widget" "$out"

# The check drives manualsteps open: shown only when a widget is placed.
cat > "$tmp/steps.list" <<'EOF'
remove-widgets|Display, keyboard & desktop|Remove every widget from the desktop: Control-click (or right-click) each widget → Remove Widget.|Desktop (reveal the desktop if the widgets are hidden)||remove-widgets
EOF

three_rc=0
three_out="$(MANUAL_STEPS_LIST="$tmp/steps.list" DESKTOP_WIDGETS_PLIST="$tmp/three.plist" \
  "$MS" check --porcelain 2>"$tmp/three.err")" || three_rc=$?
eq "3 widgets makes check warn" 1 "$three_rc"
eq "3 widgets porcelain status" warn "$(printf '%s\n' "$three_out" | awk -F'|' '{print $1; exit}')"
has "3 widgets porcelain names the count" "3 widgets on the desktop" "$three_out"
has "3 widgets porcelain names Photos" "com.apple.Photos.PhotosWidget" "$three_out"

zero_rc=0
zero_out="$(MANUAL_STEPS_LIST="$tmp/steps.list" DESKTOP_WIDGETS_PLIST="$tmp/zero.plist" \
  "$MS" check --porcelain 2>"$tmp/zero.err")" || zero_rc=$?
eq "0 widgets makes check ok" 0 "$zero_rc"
eq "0 widgets porcelain status" ok "$(printf '%s\n' "$zero_out" | awk -F'|' '{print $1; exit}')"

hand_rc=0
hand_out="$(MANUAL_STEPS_LIST="$tmp/steps.list" DESKTOP_WIDGETS_PLIST="$tmp/garbage.plist" \
  "$MS" check --porcelain 2>"$tmp/hand.err")" || hand_rc=$?
eq "unreadable plist does not fail check" 0 "$hand_rc"
eq "unreadable plist is by hand" hand "$(printf '%s\n' "$hand_out" | awk -F'|' '{print $1; exit}')"
has "unreadable porcelain says check by hand" "check by hand" "$hand_out"

open_three="$(printf 'q\n' | MANUAL_STEPS_OPEN_TTY=1 MANUAL_STEPS_LIST="$tmp/steps.list" \
  DESKTOP_WIDGETS_PLIST="$tmp/three.plist" "$MS" open 2>"$tmp/open3.err")" || true
has "open shows the step when widgets exist" \
  "Remove every widget from the desktop: Control-click (or right-click) each widget → Remove Widget." \
  "$open_three"
has "open names the desktop" "Desktop (reveal the desktop if the widgets are hidden)" "$open_three"

open_zero="$(printf 'q\n' | MANUAL_STEPS_OPEN_TTY=1 MANUAL_STEPS_LIST="$tmp/steps.list" \
  DESKTOP_WIDGETS_PLIST="$tmp/zero.plist" "$MS" open 2>"$tmp/open0.err")" || true
has "open with no widgets says nothing to do" "Nothing to do" "$open_zero"
miss "open hides the step when no widgets are placed" "Remove every widget" "$open_zero"

open_hand="$(printf 'q\n' | MANUAL_STEPS_OPEN_TTY=1 MANUAL_STEPS_LIST="$tmp/steps.list" \
  DESKTOP_WIDGETS_PLIST="$tmp/garbage.plist" "$MS" open 2>"$tmp/openh.err")" || true
has "open shows the step when the plist cannot be read" "Remove every widget" "$open_hand"

# Repo wiring. The old unchecked id stays gone; removal is remove-widgets.
LIST="$DIR/lib/manual-steps.list"
row="$(awk -F'|' '$1 == "remove-widgets" { print; exit }' "$LIST")"
eq "manual step title" \
  "Remove every widget from the desktop: Control-click (or right-click) each widget → Remove Widget." \
  "$(printf '%s\n' "$row" | cut -d'|' -f3)"
eq "manual step group" "Display, keyboard & desktop" "$(printf '%s\n' "$row" | cut -d'|' -f2)"
eq "manual step check is the named check" remove-widgets "$(printf '%s\n' "$row" | cut -d'|' -f6)"
eq "old desktop-widgets id stays gone" "" \
  "$(awk -F'|' '$1 == "desktop-widgets" { print $1; exit }' "$LIST")"
eq "remove-widgets is report-only" "PAUL|" \
  "$(awk -F'|' '$1 == "remove-widgets" { print $2 "|" $3; exit }' "$DIR/lib/autofix.list")"
has "autofix names the plist" "com.apple.notificationcenterui.plist" \
  "$(awk -F'|' '$1 == "remove-widgets" { print; exit }' "$DIR/lib/autofix.list")"
has "autofix refuses to signal NotificationCenter" "NotificationCenter" \
  "$(awk -F'|' '$1 == "remove-widgets" { print; exit }' "$DIR/lib/autofix.list")"
has "autofix refuses to signal chronod" "chronod" \
  "$(awk -F'|' '$1 == "remove-widgets" { print; exit }' "$DIR/lib/autofix.list")"

section="$(grep -vE '^[[:space:]]*#' "$DIR/checks/display.sh")"
has "display section has a Desktop widgets heading" 'hdr "Desktop widgets"' "$section"
has "display section times out the helper" 'with_timeout 15' "$section"
has "display section calls the helper" 'lib/desktop-widgets.py' "$section"
# shellcheck disable=SC2016  # needle is source text, compared literally
has "display section warns on widgets" 'warn "$widgets_msg"' "$section"
has "display section leaves an unreadable plist by hand" "check by hand" "$section"
has "display section tags the warning" 'fixid remove-widgets' "$section"
miss "display section does not killall" "killall" "$section"
miss "display section does not defaults write" "defaults write" "$section"

manual_code="$(grep -vE '^[[:space:]]*#' "$DIR/checks/manual.sh")"
has "manual section does not repeat the section on a full run" 'WIDGETS_SECTION_RAN:-}" = 1' "$manual_code"
has "a remove-widgets warning keeps its id" 'remove-widgets) fixid remove-widgets' "$manual_code"

ms_code="$(grep -vE '^[[:space:]]*#' "$MS")"
has "manual-steps runs the named check" 'remove-widgets)   check_remove_widgets' "$ms_code"
miss "manual-steps does not write the plist" "defaults write" "$ms_code"

helper_code="$(grep -vE '^[[:space:]]*#' "$HELPER")"
eq "helper does not shell out" "" "$(printf '%s\n' "$helper_code" | grep -nE 'subprocess|os\.system|Popen|killall|defaults' || true)"
miss "macos.sh does not mention the widget plist" "notificationcenterui" "$(cat "$DIR/macos.sh")"
miss "autofix lib does not mention the widget plist" "notificationcenterui" "$(cat "$DIR/lib/autofix-lib.sh")"

settings="$(cat "$DIR/docs/settings.md")"
has "settings says hiding does not delete placed widgets" "does not delete it" "$settings"
has "settings names the plist" "com.apple.notificationcenterui.plist" "$settings"
has "settings names instances" "widgets" "$settings"
has "settings says a warning counts widgets" "widgets on the desktop" "$settings"
has "settings says fix does not write the plist" "does not write that plist" "$settings"
has "settings says fix does not signal NotificationCenter" "NotificationCenter" "$settings"
has "settings names the manual removal" "Remove Widget" "$settings"

doc="$(cat "$DIR/docs/manual-steps.md")"
has "manual-steps doc names the removal" "Remove every widget from the desktop" "$doc"
has "manual-steps doc says open is conditional" "only when a widget is still placed" "$doc"
has "manual-steps doc says fix does not write the plist" "does not write that plist" "$doc"

val_rc=0
val_out="$("$MS" validate 2>"$tmp/val.err")" || val_rc=$?
eq "manual steps list validates" 0 "$val_rc"
has "validate counts the new step" "steps OK" "$val_out"

printf 'desktop-widgets tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
