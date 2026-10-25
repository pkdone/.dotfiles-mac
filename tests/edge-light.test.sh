#!/usr/bin/env bash
#
# Edge Light is Off. The on/off state cannot be read: the protected Control
# Centre video-effects file is permission denied, and RingLightHelper's group
# holds no preferences. The check never writes. The step is always shown, with
# the why-line "MANUAL: Can't be checked, so always shown". macconfig lists
# it with that same MANUAL: line.
# Run: ./tests/edge-light.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$DIR/lib/edge-light.py"
MS="$DIR/scripts/manual-steps.sh"
LIST="$DIR/lib/manual-steps.list"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "edge-light tests: python3 not found, skipped"; exit 0; fi

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

CLICK="Start a video call (or open Photo Booth / FaceTime) so the camera is on → click Control Centre in the menu bar → Video Effects → click Edge Light so it is Off"
WHY="can't be checked, so always shown"
SHOWN="MANUAL: Can't be checked, so always shown. If it's already set, press s."
AV_NAME="group.com.apple.secure-control-center-preferences.av.plist"

tmp="$(mktemp -d)"
trap 'chmod -R u+rwx "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

run_helper() { # av ringlight
  "$PY" "$HELPER" --av "$1" --ringlight "$2"
}

snapshot() { # path — empty if missing
  if [ -e "$1" ]; then
    cksum "$1" 2>/dev/null || stat -c '%a %s' "$1"
  else
    printf 'missing\n'
  fi
}

# Permission denied on the protected file. Root can still read mode 000, so
# this fixture is the unprivileged case the real Mac hits.
printf 'secret-edge-light' > "$tmp/denied.plist"
chmod 000 "$tmp/denied.plist"
mkdir -p "$tmp/ring-empty"
before="$(snapshot "$tmp/denied.plist")"
out="$(run_helper "$tmp/denied.plist" "$tmp/ring-empty")"
eq "permission denied is check by hand" "hand" "${out%%|*}"
eq "permission denied uses the always-shown line" "$WHY" "${out#*|}"
eq "permission denied does not rewrite the protected file" "$before" "$(snapshot "$tmp/denied.plist")"
eq "an empty RingLightHelper group gains no preferences" "" "$(find "$tmp/ring-empty" -type f -print)"

# The protected file is not created when it is missing.
out="$(run_helper "$tmp/no-such-av.plist" "$tmp/ring-empty")"
eq "a missing protected file is check by hand" "hand" "${out%%|*}"
eq "a missing protected file is not created" "missing" "$(snapshot "$tmp/no-such-av.plist")"

# A readable plist is still not the toggle, and it is not rewritten.
printf 'EdgeLight=1' > "$tmp/readable.plist"
before="$(snapshot "$tmp/readable.plist")"
out="$(run_helper "$tmp/readable.plist" "$tmp/ring-empty")"
eq "a readable plist is still check by hand" "hand" "${out%%|*}"
eq "a readable plist is not rewritten" "$before" "$(snapshot "$tmp/readable.plist")"
miss "a readable plist is not reported as on" "warn|" "$out"

# A decoy preference in the group is not the Edge Light state.
mkdir -p "$tmp/ring-decoy/Library/Preferences"
printf 'not-the-toggle' > "$tmp/ring-decoy/Library/Preferences/group.com.apple.ringlight.plist"
before="$(snapshot "$tmp/ring-decoy/Library/Preferences/group.com.apple.ringlight.plist")"
out="$(run_helper "$tmp/denied.plist" "$tmp/ring-decoy")"
eq "a RingLightHelper plist is still check by hand" "hand" "${out%%|*}"
eq "a RingLightHelper plist is not rewritten" "$before" "$(snapshot "$tmp/ring-decoy/Library/Preferences/group.com.apple.ringlight.plist")"

# Default paths under HOME: the protected file denied, the group empty, and
# a RingLightHelper container with no preferences.
home="$tmp/home"
av_rel="Library/Group Containers/group.com.apple.secure-control-center-preferences/Library/Preferences"
mkdir -p "$home/$av_rel" "$home/Library/Group Containers/group.com.apple.ringlight" \
  "$home/Library/Containers/com.apple.RingLightHelper"
printf 'secret-edge-light' > "$home/$av_rel/$AV_NAME"
chmod 000 "$home/$av_rel/$AV_NAME"
before_av="$(snapshot "$home/$av_rel/$AV_NAME")"
out="$(env -u EDGE_LIGHT_AV_PLIST -u EDGE_LIGHT_RINGLIGHT_DIR HOME="$home" "$PY" "$HELPER")"
eq "the default paths are check by hand" "hand" "${out%%|*}"
eq "the default paths use the always-shown line" "$WHY" "${out#*|}"
eq "the default protected file is not rewritten" "$before_av" "$(snapshot "$home/$av_rel/$AV_NAME")"
eq "the default group gains no preferences" "" \
  "$(find "$home/Library/Group Containers/group.com.apple.ringlight" -type f -print)"
eq "the RingLightHelper container gains no preferences" "" \
  "$(find "$home/Library/Containers/com.apple.RingLightHelper" -type f -print)"

helper_code="$(grep -vE '^[[:space:]]*#' "$HELPER")"
miss "helper does not dump a plist" "plistlib" "$helper_code"
miss "helper does not open a file for writing" "\"w\"" "$helper_code"
miss "helper does not call defaults" "defaults" "$helper_code"

# manualsteps: always shown, including when another step already passes.
cat > "$tmp/steps.list" <<EOF
ok-pass|Pass|Present app|On disk|app:Finder|app:/etc/passwd
edge-light|Video calls|Edge Light Off|$CLICK|app:Photo Booth|edge-light
EOF
mkdir -p "$tmp/bin"
cat > "$tmp/bin/open" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${OPEN_LOG:?}"
exit 0
EOF
chmod +x "$tmp/bin/open"
export OPEN_LOG="$tmp/open.log"
: > "$OPEN_LOG"

porc_rc=0
porc="$(HOME="$home" EDGE_LIGHT_AV_PLIST="$tmp/denied.plist" EDGE_LIGHT_RINGLIGHT_DIR="$tmp/ring-empty" \
  MANUAL_STEPS_LIST="$tmp/steps.list" "$MS" check --porcelain 2>"$tmp/porc.err")" || porc_rc=$?
eq "porcelain stays check by hand" "hand" "$(printf '%s\n' "$porc" | awk -F'|' '$3=="edge-light"{print $1}')"
eq "porcelain uses the always-shown line" "$WHY" "$(printf '%s\n' "$porc" | awk -F'|' '$3=="edge-light"{print $5}')"
eq "a by-hand step does not fail the check" 0 "$porc_rc"

open_out="$(printf 's\n' | HOME="$home" NO_COLOR=1 MANUAL_STEPS_OPEN_TTY=1 \
  EDGE_LIGHT_AV_PLIST="$tmp/denied.plist" EDGE_LIGHT_RINGLIGHT_DIR="$tmp/ring-empty" \
  MANUAL_STEPS_LIST="$tmp/steps.list" PATH="$tmp/bin:$PATH" \
  "$MS" open 2>"$tmp/open.err")"
has "open shows Edge Light" "Edge Light Off" "$open_out"
has "open shows the click-by-click text" "$CLICK" "$open_out"
has "open says it can't be checked, so always shown" "$SHOWN" "$open_out"
miss "open does not skip Edge Light as already done" "Already done, shown because of --all" "$open_out"
miss "open hides the step that already passes" "Present app" "$open_out"

pending_out="$(HOME="$home" NO_COLOR=1 EDGE_LIGHT_AV_PLIST="$tmp/denied.plist" \
  EDGE_LIGHT_RINGLIGHT_DIR="$tmp/ring-empty" MANUAL_STEPS_LIST="$tmp/steps.list" \
  "$MS" pending 2>"$tmp/pending.err")"
has "pending shows Edge Light" "Edge Light Off" "$pending_out"
has "pending uses the same why-line" "$SHOWN" "$pending_out"
miss "pending hides the step that already passes" "Present app" "$pending_out"

# macconfig's Manual steps section prints check by hand for that same result.
mac_out="$(HOME="$home" NO_COLOR=1 EDGE_LIGHT_AV_PLIST="$tmp/denied.plist" \
  EDGE_LIGHT_RINGLIGHT_DIR="$tmp/ring-empty" MANUAL_STEPS_LIST="$tmp/steps.list" \
  "$DIR/macconfig-check.sh" --only manual --no-color 2>"$tmp/mac.err")" || true
has "macconfig lists Edge Light as MANUAL" \
  "Edge Light Off — $SHOWN" "$mac_out"
miss "macconfig does not say check by hand twice" "check by hand" \
  "$(printf '%s\n' "$mac_out" | grep -F 'Edge Light' || true)"
miss "macconfig does not call Edge Light drift" "DRIFT" "$(printf '%s\n' "$mac_out" | grep -F 'Edge Light' || true)"

# Repo wiring.
row="$(awk -F'|' '$1 == "edge-light" { print; exit }' "$LIST")"
eq "edge-light row exists" 1 "$(printf '%s\n' "$row" | grep -c .)"
eq "edge-light group" "Video calls" "$(printf '%s\n' "$row" | cut -d'|' -f2)"
eq "edge-light title" "Edge Light Off" "$(printf '%s\n' "$row" | cut -d'|' -f3)"
eq "edge-light click-by-click text" "$CLICK" "$(printf '%s\n' "$row" | cut -d'|' -f4)"
eq "edge-light opens Photo Booth" "app:Photo Booth" "$(printf '%s\n' "$row" | cut -d'|' -f5)"
eq "edge-light check is the named check" "edge-light" "$(printf '%s\n' "$row" | cut -d'|' -f6)"
prev="$(awk -F'|' '
  $1 ~ /^#/ || $1 ~ /^[[:space:]]*$/ { next }
  $1 == "edge-light" { print prev; exit }
  { prev = $1 }
' "$LIST")"
eq "edge-light follows the user picture" "user-picture" "$prev"

listed="$("$MS" list)"
edge_num="$(printf '%s\n' "$listed" | sed -n 's/^ *\([0-9][0-9]*\)\. Edge Light Off$/\1/p')"
user_num="$(printf '%s\n' "$listed" | sed -n 's/^ *\([0-9][0-9]*\)\. Set your user picture.*/\1/p')"
eq "edge light is the step after the user picture" "$((user_num + 1))" "$edge_num"
has "the numbered list includes the click-by-click text" "$CLICK" "$listed"

doc="$(cat "$DIR/docs/manual-steps.md")"
# shellcheck disable=SC2016  # needle is markdown, compared literally
has "manual-steps doc names the step" 'manual step `edge-light`' "$doc"
has "manual-steps doc says it is Off" "Edge Light (manual step \`edge-light\`) is Off." "$doc"
has "manual-steps doc names the protected file" "$AV_NAME" "$doc"
has "manual-steps doc says permission denied" "permission denied" "$doc"
has "manual-steps doc names the RingLightHelper group" "group.com.apple.ringlight" "$doc"
has "manual-steps doc says nothing writes" "Nothing writes either place." "$doc"
has "manual-steps doc says the step is always shown" "always shown" "$doc"
has "manual-steps doc says macconfig lists it as MANUAL" "lists it as \`MANUAL:\`" "$doc"
has "table includes the click-by-click text" "$CLICK" "$doc"
has "table row is by hand" "| Edge Light Off | $CLICK | by hand |" "$doc"

checks="$(cat "$DIR"/checks/*.sh "$DIR/macos.sh")"
miss "no edge-light fixid" "fixid edge-light" "$checks"
eq "autofix has no edge-light row" "" \
  "$(awk -F'|' '$1 == "edge-light" { print; exit }' "$DIR/lib/autofix.list")"
miss "macos.sh does not set Edge Light" "edge-light" "$(cat "$DIR/macos.sh")"
miss "macos.sh does not name the protected file" "$AV_NAME" "$(cat "$DIR/macos.sh")"

ms_code="$(grep -vE '^[[:space:]]*#' "$MS")"
has "manual-steps runs the named check" 'edge-light)       check_edge_light' "$ms_code"
has "the why-line uses the always-shown text" "$WHY" "$ms_code"
miss "manual-steps does not write Edge Light" "defaults write" "$(sed -n '/check_edge_light/,/^}/p' "$MS")"

val_rc=0
val_out="$("$MS" validate 2>"$tmp/val.err")" || val_rc=$?
eq "manual steps list validates" 0 "$val_rc"
has "validate counts the steps" "steps OK" "$val_out"

printf 'edge-light tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
