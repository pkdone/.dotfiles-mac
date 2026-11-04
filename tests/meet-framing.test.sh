#!/usr/bin/env bash
#
# Framing Off in Google Meet is a manual step. The toggle lives in the Meet
# web app and the Google account, so the check stays empty. Nothing reads a
# Chrome profile for it and nothing writes one.
# Run: ./tests/meet-framing.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hermetic.sh disable=SC1091
. "$DIR/tests/hermetic.sh"
MS="$DIR/scripts/manual-steps.sh"
LIST="$DIR/lib/manual-steps.list"
DOC="$DIR/docs/manual-steps.md"

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

TITLE="Framing Off in Google Meet"
WHERE="In a Google Meet call, with the camera on, open Backgrounds and effects → Appearance tab → turn Framing off. The toggle says it puts you in the center of the screen. Settings → Video only says video enhancement has moved. Leave macOS Centre Stage as it is"
MANUAL="MANUAL: Can't check this automatically. If it's already set, press s."

row="$(awk -F'|' '$1 == "meet-framing" { print; exit }' "$LIST")"
eq "meet-framing row exists" 1 "$(printf '%s\n' "$row" | grep -c .)"
eq "meet-framing group" "Video calls" "$(printf '%s\n' "$row" | cut -d'|' -f2)"
eq "meet-framing title" "$TITLE" "$(printf '%s\n' "$row" | cut -d'|' -f3)"
eq "meet-framing where" "$WHERE" "$(printf '%s\n' "$row" | cut -d'|' -f4)"
eq "meet-framing opens Meet" "https://meet.google.com" "$(printf '%s\n' "$row" | cut -d'|' -f5)"
eq "meet-framing check is empty" "" "$(printf '%s\n' "$row" | cut -d'|' -f6)"

prev="$(awk -F'|' '
  $1 ~ /^#/ || $1 ~ /^[[:space:]]*$/ { next }
  $1 == "meet-framing" { print prev; exit }
  { prev = $1 }
' "$LIST")"
eq "meet-framing follows Center Stage" "zoom-center-stage" "$prev"
next="$(awk -F'|' '
  $1 ~ /^#/ || $1 ~ /^[[:space:]]*$/ { next }
  seen { print $1; exit }
  $1 == "meet-framing" { seen = 1 }
' "$LIST")"
eq "meet-framing is the last Video calls step" "home-printer" "$next"
has "the list comment forbids a Chrome profile read" \
  "Do not read a Chrome profile to guess it, and do not write one." \
  "$(awk '
    /^meet-framing\|/ { exit }
    { buf = buf $0 "\n" }
    END { print buf }
  ' "$LIST")"

doc="$(cat "$DOC")"
settings="$(cat "$DIR/docs/settings.md")"
trouble="$(cat "$DIR/docs/troubleshooting.md")"
# shellcheck disable=SC2016  # needles are markdown, compared literally
has "settings names the step" 'manual step `meet-framing`' "$settings"
has "settings says it is Off in Google Meet" "is Off in Google Meet." "$settings"
has "settings names the zoomed-in camera" "zooms the built-in MacBook camera in too far." "$settings"
has "settings names Backgrounds and effects" "Backgrounds and effects" "$settings"
has "settings names the Appearance tab" "Appearance tab" "$settings"
has "settings quotes the toggle" "puts you in the center of the screen." "$settings"
has "settings names the moved Video page" "video enhancement has moved" "$settings"
has "settings leaves Centre Stage as it is" "macOS Centre Stage stays as it is." "$settings"
# shellcheck disable=SC2016
has "settings says no plist holds it" 'No `defaults` domain and no plist under `~/Library` holds it.' "$settings"
has "settings leaves the Chrome profile unread" "Nothing reads a Chrome profile for it and nothing writes one." "$settings"
has "settings uses the MANUAL line" "label the step \`$MANUAL\`" "$settings"
has "settings points at troubleshooting" "troubleshooting.md#google-meet-framing" "$settings"
has "manual-steps doc lists it with the other by-hand settings" \
  "Google Meet Framing, and Automatically adjust brightness" "$doc"
# shellcheck disable=SC2016  # needle is markdown, compared literally
has "manual-steps doc links the step" 'manual step `meet-framing`' "$doc"
has "table row is by hand" "| $TITLE | $WHERE | by hand |" "$doc"
# shellcheck disable=SC2016  # needle is markdown, compared literally
has "troubleshooting names the step" 'manual step `meet-framing`' "$trouble"
has "troubleshooting names the Appearance tab" "Appearance tab" "$trouble"
has "troubleshooting points at By hand" "settings.md#by-hand" "$trouble"

checks="$(cat "$DIR"/checks/*.sh "$DIR/macos.sh" "$DIR/macconfig-check.sh")"
miss "no meet-framing fixid" "fixid meet-framing" "$checks"
eq "autofix has no meet-framing row" "" \
  "$(awk -F'|' '$1 == "meet-framing" { print; exit }' "$DIR/lib/autofix.list")"
miss "manual-steps.sh does not special-case Framing" "meet-framing" "$(cat "$MS")"
miss "covered-steps does not special-case Framing" "meet-framing" \
  "$(cat "$DIR/lib/covered-steps.sh")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"
mkdir -p "$bin"
cat > "$bin/open" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${OPEN_LOG:?}"
exit 0
EOF
chmod +x "$bin/open"
SAFE="$(hermetic_safe_root)"
printf '%s\n' "$row" > "$tmp/steps.list"
export NO_COLOR=1 OPEN_LOG="$tmp/open.log"
: > "$OPEN_LOG"

porc_rc=0
porc="$(PATH="$bin:$SAFE" MANUAL_STEPS_LIST="$tmp/steps.list" \
  "$MS" check --porcelain 2>"$tmp/porc.err")" || porc_rc=$?
eq "porcelain is by hand" "hand" "$(printf '%s\n' "$porc" | cut -d'|' -f1)"
eq "porcelain names the step" "meet-framing" "$(printf '%s\n' "$porc" | cut -d'|' -f3)"
eq "porcelain has no detail" "" "$(printf '%s\n' "$porc" | cut -d'|' -f5)"
eq "a by-hand step does not fail the check" 0 "$porc_rc"

pending_out="$(PATH="$bin:$SAFE" MANUAL_STEPS_LIST="$tmp/steps.list" \
  "$MS" pending 2>"$tmp/pending.err")"
has "pending shows the step" "$TITLE" "$pending_out"
has "pending uses the MANUAL line" "$MANUAL" "$pending_out"
has "pending shows the click-by-click text" "$WHERE" "$pending_out"

open_out="$(printf '\n\n' | PATH="$bin:$SAFE" MANUAL_STEPS_OPEN_TTY=1 \
  MANUAL_STEPS_LIST="$tmp/steps.list" "$MS" open 2>"$tmp/open.err")"
has "open shows the step" "$TITLE" "$open_out"
has "open uses the MANUAL line" "$MANUAL" "$open_out"
miss "open has something to open" "(nothing to open)" "$open_out"
eq "open launches Meet" "https://meet.google.com" "$(cat "$OPEN_LOG")"

mac_out="$(PATH="$bin:$SAFE" MANUAL_STEPS_LIST="$tmp/steps.list" \
  "$DIR/macconfig-check.sh" --only manual --no-color 2>"$tmp/mac.err")" || true
has "macconfig lists the step as MANUAL" "$TITLE — $MANUAL" "$mac_out"
miss "macconfig does not call it drift" "DRIFT" \
  "$(printf '%s\n' "$mac_out" | grep -F "$TITLE" || true)"

printf 'meet-framing tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
