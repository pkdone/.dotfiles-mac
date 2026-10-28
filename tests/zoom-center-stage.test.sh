#!/usr/bin/env bash
#
# Center Stage Off for Zoom is a manual step. macOS keeps per-app Video
# Effects in the system camera service, not in a user preference, so the
# check stays empty. Nothing reads or writes a plist for it.
# Run: ./tests/zoom-center-stage.test.sh
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

TITLE="Center Stage Off for Zoom"
WHERE="Start a Zoom call or test video (Zoom → Settings → Video) with the camera on → click the green camera icon in the menu bar → under MacBook Pro Camera, turn off Centre Stage. macOS remembers this per app"
MANUAL="MANUAL: Can't check this automatically. If it's already set, press s."

row="$(awk -F'|' '$1 == "zoom-center-stage" { print; exit }' "$LIST")"
eq "zoom-center-stage row exists" 1 "$(printf '%s\n' "$row" | grep -c .)"
eq "zoom-center-stage group" "Video calls" "$(printf '%s\n' "$row" | cut -d'|' -f2)"
eq "zoom-center-stage title" "$TITLE" "$(printf '%s\n' "$row" | cut -d'|' -f3)"
eq "zoom-center-stage where" "$WHERE" "$(printf '%s\n' "$row" | cut -d'|' -f4)"
eq "zoom-center-stage opens Zoom" "app:zoom.us" "$(printf '%s\n' "$row" | cut -d'|' -f5)"
eq "zoom-center-stage check is empty" "" "$(printf '%s\n' "$row" | cut -d'|' -f6)"

prev="$(awk -F'|' '
  $1 ~ /^#/ || $1 ~ /^[[:space:]]*$/ { next }
  $1 == "zoom-center-stage" { print prev; exit }
  { prev = $1 }
' "$LIST")"
eq "zoom-center-stage follows Edge Light" "edge-light" "$prev"
has "the list comment forbids a guessed key" \
  "Do not add a check that guesses a key, and" \
  "$(awk '
    /^zoom-center-stage\|/ { exit }
    { buf = buf $0 "\n" }
    END { print buf }
  ' "$LIST")"

doc="$(cat "$DOC")"
# shellcheck disable=SC2016  # needles are markdown, compared literally
has "manual-steps doc names the step" 'manual step `zoom-center-stage`' "$doc"
has "manual-steps doc says it is Off for Zoom" "is Off for Zoom." "$doc"
has "manual-steps doc says it is per app" "macOS remembers this per app" "$doc"
has "manual-steps doc names the camera service" "in the system camera service, not in a user preference." "$doc"
# shellcheck disable=SC2016
has "manual-steps doc says no plist holds it" 'No `defaults` domain and no plist under `~/Library` holds it.' "$doc"
has "manual-steps doc says nothing reads or writes it" "Nothing reads it and nothing writes it." "$doc"
has "manual-steps doc uses the MANUAL line" "label the step \`$MANUAL\`" "$doc"
has "manual-steps doc lists it with the other by-hand settings" \
  "the Control Centre tiles, Center Stage for Zoom, the battery charge limit" "$doc"
has "table row is by hand" "| $TITLE | $WHERE | by hand |" "$doc"

checks="$(cat "$DIR"/checks/*.sh "$DIR/macos.sh" "$DIR/macconfig-check.sh")"
miss "no zoom-center-stage fixid" "fixid zoom-center-stage" "$checks"
eq "autofix has no zoom-center-stage row" "" \
  "$(awk -F'|' '$1 == "zoom-center-stage" { print; exit }' "$DIR/lib/autofix.list")"
miss "manual-steps.sh does not special-case Center Stage" "zoom-center-stage" "$(cat "$MS")"
miss "covered-steps does not special-case Center Stage" "zoom-center-stage" \
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
eq "porcelain names the step" "zoom-center-stage" "$(printf '%s\n' "$porc" | cut -d'|' -f3)"
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
eq "open launches Zoom" "-a zoom.us" "$(cat "$OPEN_LOG")"

mac_out="$(PATH="$bin:$SAFE" MANUAL_STEPS_LIST="$tmp/steps.list" \
  "$DIR/macconfig-check.sh" --only manual --no-color 2>"$tmp/mac.err")" || true
has "macconfig lists the step as MANUAL" "$TITLE — $MANUAL" "$mac_out"
miss "macconfig does not call it drift" "DRIFT" \
  "$(printf '%s\n' "$mac_out" | grep -F "$TITLE" || true)"

printf 'zoom-center-stage tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
