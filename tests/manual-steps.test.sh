#!/usr/bin/env bash
#
# Unit tests for scripts/manual-steps.sh's list parser (lib/manual-steps.list).
# Plain bash, no framework; runs on Linux CI too (list/validate don't touch macOS).
# Run: ./tests/manual-steps.test.sh   (exits non-zero if any assertion fails)
#
set -uo pipefail   # deliberately not -e: run every assertion, then tally failures

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MS="$DIR/../scripts/manual-steps.sh"
LIST="$DIR/../lib/manual-steps.list"
export NO_COLOR=1

pass=0
fail=0
eq() {  # DESCRIPTION EXPECTED ACTUAL
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"
  fi
}
has() {  # DESCRIPTION NEEDLE HAYSTACK
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n' "$1" "$2" ;;
  esac
}

# ---- the real list is well-formed -----------------------------------------
out="$("$MS" validate 2>&1)"; rc=$?
eq "real list validates" 0 "$rc"
[ "$rc" -eq 0 ] || printf '%s\n' "$out"

eq "apple-account step is gone" "" "$(awk -F'|' '$1 == "apple-account" { print; exit }' "$LIST")"
eq "icloud-sync step is gone" "" "$(awk -F'|' '$1 == "icloud-sync" { print; exit }' "$LIST")"

rows="$(grep -cEv '^[[:space:]]*(#|$)' "$LIST")"
listed="$("$MS" list | grep -cE '^ +[0-9]+\. ')"
eq "list prints one numbered line per row" "$rows" "$listed"

nums="$("$MS" list | sed -nE 's/^ +([0-9]+)\. .*/\1/p' | tr '\n' ' ')"
eq "numbering is 1..N with no gaps" "$(seq 1 "$rows" | tr '\n' ' ')" "$nums"

md_rows="$("$MS" list --markdown | grep -cE '^\| [0-9]+ \|')"
eq "markdown has one row per step" "$rows" "$md_rows"

# docs/manual-steps.md is generated (refresh: scripts/render-manual-steps-doc.sh).
RENDER="$DIR/../scripts/render-manual-steps-doc.sh"
out="$("$RENDER" --check 2>&1)"; rc=$?
eq "docs/manual-steps.md matches lib/manual-steps.list" 0 "$rc"
[ "$rc" -eq 0 ] || printf '%s\n' "$out"

doc_rows="$(grep -E '^\| [0-9]+ \|' "$DIR/../docs/manual-steps.md")"
eq "docs/manual-steps.md table matches lib/manual-steps.list" \
  "$("$MS" list --markdown | grep -E '^\| [0-9]+ \|')" "$doc_rows"
doc="$(cat "$DIR/../docs/manual-steps.md")"
ax_where="$(awk -F'|' '$1 == "hammerspoon-ax" || $1 == "karabiner-ax" || $1 == "raycast-ax" { print $1 "|" $4 }' "$LIST")"
eq "accessibility steps use Privacy & Security → Accessibility" \
  "$(printf '%s\n' \
    'hammerspoon-ax|System Settings → Privacy & Security → Accessibility → Hammerspoon' \
    'karabiner-ax|System Settings → Privacy & Security → Accessibility' \
    'raycast-ax|System Settings → Privacy & Security → Accessibility → Raycast')" \
  "$ax_where"
eq "step paths do not use the newer page name" "" \
  "$(awk -F'|' '$4 ~ /Device Control/ { print }' "$LIST")"
eq "newer page name is mentioned once, in the manual-steps doc" 1 \
  "$(grep -c 'Device Control and Data Access' "$DIR/../docs/manual-steps.md")"
eq "setup doc uses Accessibility for that page" "" \
  "$(grep -F 'Device Control' "$DIR/../docs/setup.md" || true)"
eq "settings doc uses Accessibility for that page" "" \
  "$(grep -F 'Device Control' "$DIR/../docs/settings.md" || true)"
eq "README does not use the newer page name" "" \
  "$(grep -F 'Device Control' "$DIR/../README.md" || true)"
eq "manual-steps doc does not name Apple Account" "" "$(printf '%s\n' "$doc" | grep -F 'Apple Account' || true)"
eq "manual-steps doc does not mention iCloud Keychain" "" "$(printf '%s\n' "$doc" | grep -F 'iCloud Keychain' || true)"

# ---- malformed rows are reported ------------------------------------------
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<'ROWS'
# comment line
good-one|Group A|Title|Where||
good-two|Group A|Title|Where|x-apple.systempreferences:com.apple.Trackpad-Settings.extension|defaults:com.apple.AppleMultitouchTrackpad:Clicking=1
good-one|Group A|Duplicate id|Where||
Bad_Id|Group A|Title|Where||
too-many|Group A|Title|Where|||extra
no-title|Group A||Where||
bad-open|Group A|Title|Where|ftp://nope|
bad-check|Group A|Title|Where||frobnicate
bad-tcc|Group A|Title|Where||tcc:Accessibility:com.evil';drop
bad-logi|Group A|Title|Where||logi:wheel-smooth;rm
split|Group B|Title|Where||
split-2|Group A|Title|Where||app:Finder
ROWS
out="$(MANUAL_STEPS_LIST="$tmp" "$MS" validate 2>&1)"; rc=$?
eq "malformed list fails validate" 1 "$rc"
has "duplicate id"      "duplicate id 'good-one'" "$out"
has "kebab-case id"     "id 'Bad_Id' must be kebab-case" "$out"
has "too many fields"   "too many fields" "$out"
has "required fields"   "id, group, title and where are required" "$out"
has "bad open target"   "open 'ftp://nope'" "$out"
has "unknown check"     "unknown check 'frobnicate'" "$out"
has "unsafe tcc spec"   "unknown check 'tcc:Accessibility:com.evil';drop'" "$out"
has "unsafe logi spec"  "unknown check 'logi:wheel-smooth;rm'" "$out"
has "split group"       "group 'Group A' is split" "$out"

# Bad rows are skipped (with a warning) so list still prints the good ones.
good="$(MANUAL_STEPS_LIST="$tmp" "$MS" list 2>/dev/null | grep -cE '^ +[0-9]+\. ')"
eq "list skips rows with missing/extra fields" 10 "$good"

# ---- trackpad preferences moved to lib/macos-defaults.list ---------------
DEF="$DIR/../lib/macos-defaults.list"
miss() {  # DESCRIPTION NEEDLE HAYSTACK
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n' "$1" "$2" ;;
    *) pass=$((pass + 1)) ;;
  esac
}
real_ids="$(grep -E '^[^#[:space:]]' "$LIST" | cut -d'|' -f1)"
for gone in trackpad-tap-to-click trackpad-click-light trackpad-secondary-click \
            trackpad-tracking-speed trackpad-three-finger-drag trackpad-lookup-force-click \
            desktop-widgets; do
  miss "manual step $gone moved out" "$gone" "$real_ids"
done
steps_text="$(cat "$LIST")"
has "look up stays a manual note" "trackpad-lookup|Trackpad, mouse & pointer|Trackpad: Look up & data detectors Off|" "$steps_text"
has "dragging stays a check" "defaults:com.apple.AppleMultitouchTrackpad:Dragging=1,DragLock=0" "$steps_text"
miss "look up note does not mention Force Click" "Force Click" "$(grep '^trackpad-lookup|' "$LIST")"

# Exact rows macos.sh applies and macconfig-check.sh checks. restart=logout.
for row in \
  'com.apple.AppleMultitouchTrackpad|Clicking|int|1|logout|Trackpad|Tap to click|' \
  'com.apple.driver.AppleBluetoothMultitouch.trackpad|Clicking|int|1|logout|Trackpad|Tap to click (Bluetooth trackpad)|' \
  'NSGlobalDomain|com.apple.mouse.tapBehavior|int|1|logout|Trackpad|Tap to click behavior|' \
  'com.apple.AppleMultitouchTrackpad|FirstClickThreshold|int|0|logout|Trackpad|Click pressure|' \
  'com.apple.AppleMultitouchTrackpad|TrackpadCornerSecondaryClick|int|2|logout|Trackpad|Secondary click corner|' \
  'com.apple.AppleMultitouchTrackpad|TrackpadRightClick|int|0|logout|Trackpad|Secondary click on the right side|' \
  'com.apple.AppleMultitouchTrackpad|TrackpadThreeFingerDrag|int|0|logout|Trackpad|Three-finger drag|' \
  'NSGlobalDomain|com.apple.trackpad.scaling|float|0.6875|logout|Trackpad|Tracking speed|' \
  'com.apple.AppleMultitouchTrackpad|ActuateDetents|int|1|logout|Trackpad|Force Click|' \
  'com.apple.AppleMultitouchTrackpad|ForceSuppressed|int|0|logout|Trackpad|Haptic feedback|'
do
  has "defaults row ${row%%|*}" "$row" "$(grep -v '^#' "$DEF")"
done
miss "dragging is not written by macos.sh" '|Dragging|' "$(grep -v '^#' "$DEF")"
miss "drag lock is not written by macos.sh" '|DragLock|' "$(grep -v '^#' "$DEF")"

# Mouse tracking and scrolling are a check only (same idea as dragging).
mouse_row="$(grep '^mouse-settings|' "$LIST")"
has "mouse step checks tracking speed" "com.apple.mouse.scaling=1.5" "$mouse_row"
has "mouse step checks scrolling speed" "com.apple.scrollwheel.scaling=0.5" "$mouse_row"
has "mouse step still names double-click" "Double-click" "$mouse_row"
has "mouse step still names secondary click" "secondary click" "$mouse_row"
miss "mouse scaling is not written by macos.sh" 'com.apple.mouse.scaling' "$(grep -v '^#' "$DEF")"
miss "scrollwheel scaling is not written by macos.sh" 'com.apple.scrollwheel.scaling' "$(grep -v '^#' "$DEF")"
eq "mouse-settings is check-only Needs Paul" "PAUL|" \
  "$(awk -F'|' '$1 == "mouse-settings" { print $2 "|" $3; exit }' "$DIR/../lib/autofix.list")"
has "a mouse warn is tagged mouse-settings" 'mouse-settings) fixid mouse-settings' \
  "$(cat "$DIR/../checks/manual.sh")"

# Docs that used to say Force Click Off now say On.
force_off="$(grep -n -i -E 'force click[^\n]*off|haptic feedback off' \
  "$DIR/../README.md" "$DIR"/../docs/*.md "$LIST" "$DEF" "$DIR/../macos.sh" "$DIR/../lib/autofix.list" || true)"
eq "no doc still says Force Click Off" "" "$force_off"

printf 'manual-steps tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
