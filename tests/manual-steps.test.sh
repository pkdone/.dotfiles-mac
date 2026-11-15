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
ax_where="$(awk -F'|' '$1 == "karabiner-ax" || $1 == "raycast-ax" { print $1 "|" $4 }' "$LIST")"
eq "accessibility steps use Privacy & Security → Accessibility" \
  "$(printf '%s\n' \
    'karabiner-ax|Open Karabiner-Elements first. System Settings → Privacy & Security → Accessibility. If it is not listed, click + and add it from Applications' \
    'raycast-ax|Open Raycast first. System Settings → Privacy & Security → Accessibility. If it is not listed, click + and add it from Applications')" \
  "$ax_where"
hs_where="$(awk -F'|' '$1 == "hammerspoon-ax" { print $4 }' "$LIST")"
has "hammerspoon step opens Accessibility" \
  "Open Hammerspoon first. System Settings → Privacy & Security → Accessibility. If it is not listed, click + and add it from Applications." \
  "$hs_where"
has "hammerspoon step says there is no menu-bar icon" "There is no menu-bar icon." "$hs_where"
has "hammerspoon step names reload" "hs.reload()" "$hs_where"
has "hammerspoon step names the console" "hs.openConsole()" "$hs_where"
has "hammerspoon step names Spotlight or Raycast" "Spotlight or Raycast" "$hs_where"
eq "driver step says to open Karabiner-Elements first" \
  "Open Karabiner-Elements first so it asks for its driver." \
  "$(awk -F'|' '$1=="karabiner-driver" { print $4 }' "$LIST" | cut -d. -f1)."
eq "step paths do not use the newer page name" "" \
  "$(awk -F'|' '$4 ~ /Device Control/ { print }' "$LIST")"
eq "manual-steps doc does not use the newer page name" "" \
  "$(grep -F 'Device Control' "$DIR/../docs/manual-steps.md" || true)"
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
has "dragging names the Trackpad Options sheet" \
  "click Trackpad Options… (opens a sheet)" "$(grep '^trackpad-dragging|' "$LIST")"
has "input sources name the Edit sheet" \
  "click Edit… next to Input Sources (opens a sheet)" "$(grep '^input-british|' "$LIST")"
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
# The step names slider notches: 1.5 is the 7th from Slow, 0.5 the 5th.
mouse_row="$(grep '^mouse-settings|' "$LIST")"
has "mouse step checks tracking speed" "com.apple.mouse.scaling=1.5" "$mouse_row"
has "mouse step checks scrolling speed" "com.apple.scrollwheel.scaling=0.5" "$mouse_row"
has "mouse step names the tracking notch" "7th notch from Slow" "$mouse_row"
has "mouse step names the scrolling notch" "5th notch from Slow" "$mouse_row"
has "mouse step still names double-click" "Double-Click Speed" "$mouse_row"
has "mouse step still names Click Right Side" "Click Right Side" "$mouse_row"
has "mouse warning names the tracking notch" "7th notch from Slow" \
  "$(awk -F'|' '$1 == "mouse-settings" { print $4; exit }' "$DIR/../lib/autofix.list")"
has "mouse warning names the scrolling notch" "5th notch from Slow" \
  "$(awk -F'|' '$1 == "mouse-settings" { print $4; exit }' "$DIR/../lib/autofix.list")"
miss "mouse scaling is not written by macos.sh" 'com.apple.mouse.scaling' "$(grep -v '^#' "$DEF")"
miss "scrollwheel scaling is not written by macos.sh" 'com.apple.scrollwheel.scaling' "$(grep -v '^#' "$DEF")"
eq "mouse-settings is check-only Needs Paul" "PAUL|" \
  "$(awk -F'|' '$1 == "mouse-settings" { print $2 "|" $3; exit }' "$DIR/../lib/autofix.list")"
has "a mouse warn is tagged mouse-settings" 'mouse-settings) fixid mouse-settings' \
  "$(cat "$DIR/../checks/manual.sh")"

# Logi Options+ 2.9: backup stays under Settings → Other. Sign in first, and
# restore from the same page on a new Mac.
logi_row="$(grep '^logi-cloud-backup|' "$LIST")"
has "logi backup path stays Settings Other" \
  "Logi Options+ → MX Master 3S → Settings → Other → Automatically backup all devices" \
  "$logi_row"
has "logi backup says sign in first" "sign in to your Logi account first" "$logi_row"
has "logi backup names restore" "Restore settings from backup (same page) on a new Mac if needed" "$logi_row"

# Raycast is set by hand: hotkey, then Clipboard History.
raycast_ids="$(awk -F'|' '$1 ~ /^raycast-/ { printf "%s ", $1 }' "$LIST")"
eq "raycast steps: accessibility, hotkey, clipboard" \
  "raycast-ax raycast-hotkey raycast-clipboard " \
  "$raycast_ids"
hotkey_row="$(grep '^raycast-hotkey|' "$LIST")"
has "hotkey path records the shortcut" \
  "Open Raycast → Settings (Command+,) → General → Raycast Hotkey → click the hotkey recorder and press Shift+Control+Command+R" \
  "$hotkey_row"
has "hotkey step says not to replace Spotlight" \
  "Don't click the Replace Spotlight button" \
  "$hotkey_row"
clip_row="$(grep '^raycast-clipboard|' "$LIST")"
has "clipboard path uses the Clipboard History sidebar" \
  "Raycast Settings → Clipboard History (in the left sidebar; there is no Extensions tab)" \
  "$clip_row"
has "clipboard path names Keep history for" "Keep history for" "$clip_row"
has "clipboard path names Disabled Applications" "Disabled Applications" "$clip_row"
has "clipboard path names Add Hotkey" "Add Hotkey" "$clip_row"
has "clipboard path names the apps already listed" \
  "Keychain Access and Passwords are already listed" \
  "$clip_row"
miss "no raycast import step" "raycast-import|" "$steps_text"
miss "no finder unbind step" "raycast-finder-unbind|" "$steps_text"
miss "no scheduled backup step" "raycast-scheduled-backup|" "$steps_text"
miss "no unbind-the-Finder-hotkey step" \
  "Only if you imported a backup: unbind the Finder hotkey" "$steps_text"
# Docs, the checklist, bootstrap, and macconfig do not mention a Raycast
# backup, import, export, or .rayconfig. Logi cloud backup is a different step.
raycast_surfaces="$(
  cat "$DIR/../docs/"*.md "$LIST" "$DIR/../bootstrap.sh" "$DIR/../macconfig-check.sh" \
    "$DIR/../scripts/manual-steps.sh" "$DIR/../macos.sh"
)"
raycast_backup_lines="$(printf '%s\n' "$raycast_surfaces" | grep -n -i -E 'raycast.{0,80}(backup|import|export|rayconfig)|(backup|import|export|rayconfig).{0,80}raycast' || true)"
eq "no Raycast backup, import, export, or .rayconfig note" "" "$raycast_backup_lines"

# Docs that used to say Force Click Off now say On.
force_off="$(grep -n -i -E 'force click[^\n]*off|haptic feedback off' \
  "$DIR/../README.md" "$DIR"/../docs/*.md "$LIST" "$DEF" "$DIR/../macos.sh" "$DIR/../lib/autofix.list" || true)"
eq "no doc still says Force Click Off" "" "$force_off"

# Current Raycast does not store raycastGlobalHotkey. A missing key is check
# by hand. A stored value that differs is a warning. Another defaults step
# still warns when its key is missing.
raydir="$(mktemp -d)"
cat > "$raydir/defaults" <<'EOF'
#!/bin/sh
[ "$1" = read ] || exit 1
domain="$2"
key="${3:-}"
if [ "$domain" = com.raycast.macos ] && [ -z "$key" ]; then
  exit 0
fi
if [ "$domain" = com.raycast.macos ]; then
  case "${RAYCAST_KEY:-missing}" in
    missing) exit 1 ;;
    *) printf '%s\n' "$RAYCAST_KEY"; exit 0 ;;
  esac
fi
if [ "$domain" = NSGlobalDomain ] && [ -z "$key" ]; then
  exit 0
fi
exit 1
EOF
chmod +x "$raydir/defaults"
printf '%s\n' \
  'raycast-hotkey|App settings|Raycast hotkey|Raycast|app:Raycast|defaults:com.raycast.macos:raycastGlobalHotkey=Shift-Control-Command-15' \
  > "$raydir/raycast.list"
printf '%s\n' \
  'mouse-settings|Trackpad, mouse & pointer|Mouse|System Settings → Mouse|x-apple.systempreferences:com.apple.Mouse-Settings.extension|defaults:NSGlobalDomain:com.apple.mouse.scaling=1.5' \
  > "$raydir/mouse.list"
ray_status() {
  RAYCAST_KEY="${1:-missing}" PATH="$raydir:$PATH" MANUAL_STEPS_LIST="$raydir/raycast.list" \
    "$MS" check --porcelain 2>"$raydir/ray.err"
}
ray_out="$(ray_status missing)"
ray_rc=$?
eq "a missing Raycast hotkey is check by hand" hand "$(printf '%s\n' "$ray_out" | cut -d'|' -f1)"
eq "a missing Raycast hotkey exits 0" 0 "$ray_rc"
has "a missing Raycast hotkey says it can't be checked" "can't be checked" "$ray_out"
ray_out="$(ray_status 'Option-Space')"
eq "a different Raycast hotkey warns" warn "$(printf '%s\n' "$ray_out" | cut -d'|' -f1)"
has "a different Raycast hotkey names the stored value" "Option-Space" "$ray_out"
ray_out="$(ray_status 'Shift-Control-Command-15')"
eq "the Raycast hotkey passes when stored" ok "$(printf '%s\n' "$ray_out" | cut -d'|' -f1)"
mouse_out="$(PATH="$raydir:$PATH" MANUAL_STEPS_LIST="$raydir/mouse.list" "$MS" check --porcelain)"
eq "a missing mouse key still warns" warn "$(printf '%s\n' "$mouse_out" | cut -d'|' -f1)"
rm -rf "$raydir"

# Control Centre tiles (Edit Controls) stay a check-by-hand step. The layout
# file keeps old module instances, so there is no macconfig check and nothing
# writes a plist. The walk-through uses the empty-check label.
cc_row="$(grep '^control-centre-controls|' "$LIST")"
eq "control-centre row exists" 1 "$(printf '%s\n' "$cc_row" | grep -c .)"
eq "control-centre group" "Menu bar" "$(printf '%s\n' "$cc_row" | cut -d'|' -f2)"
eq "control-centre title" \
  "Control Centre: remove AirDrop, Stage Manager, Dark Mode, Screenshot and Focus. Keep Screen Mirroring, Wi-Fi, Bluetooth, Now Playing, Display, Sound and Keyboard Brightness." \
  "$(printf '%s\n' "$cc_row" | cut -d'|' -f3)"
eq "control-centre where" \
  "Click Control Centre in the menu bar → Edit Controls → remove AirDrop, Stage Manager, Dark Mode, Screenshot and Focus (click the minus on each, or drag it out) → Done. Clicking Done is what saves it." \
  "$(printf '%s\n' "$cc_row" | cut -d'|' -f4)"
eq "control-centre opens nothing" "" "$(printf '%s\n' "$cc_row" | cut -d'|' -f5)"
eq "control-centre check is empty" "" "$(printf '%s\n' "$cc_row" | cut -d'|' -f6)"
cc_prev="$(awk -F'|' '
  $1 ~ /^#/ || $1 ~ /^[[:space:]]*$/ { next }
  $1 == "control-centre-controls" { print prev; exit }
  { prev = $1 }
' "$LIST")"
eq "control-centre follows the menu bar allow-list" "menubar-third-party-hide" "$cc_prev"
has "control-centre comment forbids a macconfig check" \
  "Do not add a macconfig check and do not write that plist." \
  "$(awk '
    /^control-centre-controls\|/ { exit }
    { buf = buf $0 "\n" }
    END { print buf }
  ' "$LIST")"

settings="$(cat "$DIR/../docs/settings.md")"
# shellcheck disable=SC2016  # needles are markdown, compared literally
has "manual-steps doc names the Control Centre step" 'manual step `control-centre-controls`' "$doc"
has "manual-steps doc keeps Keyboard Brightness" \
  "Sound and Keyboard Brightness" "$doc"
has "manual-steps doc lists Control Centre tiles with the other by-hand settings" \
  "the Control Centre tiles" "$doc"
has "settings names the layout file" \
  'com.apple.controlcenter.bentoboxes.<host UUID>.plist' "$settings"
has "settings names the nested format" "undocumented nested binary format" "$settings"
has "settings names the date the file was stale" "On 25 Oct 2026" "$settings"
has "settings names the stale modules" "still listed AirDrop and FocusModes" "$settings"
has "settings says a tile cannot be read" \
  "so it can't tell whether a tile is showing." "$settings"
has "settings writes nothing for the tile file" "Nothing writes that file. The step stays by hand." "$settings"
has "settings names the group container" "trackedApplications" "$settings"
has "settings says the integers are menu-bar rows" \
  "Bluetooth is \`2\` (Show in Menu Bar) and Now Playing is \`8\` (Don't Show)" "$settings"
has "table row is by hand" \
  "| Control Centre: remove AirDrop, Stage Manager, Dark Mode, Screenshot and Focus. Keep Screen Mirroring, Wi-Fi, Bluetooth, Now Playing, Display, Sound and Keyboard Brightness. | Click Control Centre in the menu bar → Edit Controls → remove AirDrop, Stage Manager, Dark Mode, Screenshot and Focus (click the minus on each, or drag it out) → Done. Clicking Done is what saves it. | by hand |" \
  "$doc"
has "settings names the Control Centre keep list" \
  "Screen Mirroring, Wi-Fi, Bluetooth, Now Playing, Display, Sound and Keyboard Brightness" \
  "$settings"
has "settings says Keyboard Brightness is not a menu-bar pin" \
  "Keyboard Brightness stays in Control Centre and is not a menu-bar pin" \
  "$settings"

cc_checks="$(cat "$DIR"/../checks/*.sh "$DIR/../macos.sh" "$DIR/../macconfig-check.sh")"
miss "no control-centre fixid" "fixid control-centre" "$cc_checks"
miss "checks do not name the layout file" "bentoboxes" "$cc_checks"
eq "autofix has no control-centre row" "" \
  "$(awk -F'|' '$1 == "control-centre-controls" { print; exit }' "$DIR/../lib/autofix.list")"
miss "manual-steps.sh does not special-case Control Centre" "control-centre-controls" \
  "$(cat "$MS")"

ccdir="$(mktemp -d)"
printf '%s\n' "$cc_row" > "$ccdir/cc.list"
mkdir -p "$ccdir/bin"
cat > "$ccdir/bin/open" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$ccdir/bin/open"
cc_porc="$(NO_COLOR=1 MANUAL_STEPS_LIST="$ccdir/cc.list" "$MS" check --porcelain 2>"$ccdir/porc.err")"
eq "control centre porcelain is by hand" "hand" "$(printf '%s\n' "$cc_porc" | cut -d'|' -f1)"
eq "control centre porcelain has no detail" "" "$(printf '%s\n' "$cc_porc" | awk -F'|' '{ print $5 }')"
cc_pending="$(NO_COLOR=1 MANUAL_STEPS_LIST="$ccdir/cc.list" "$MS" pending 2>"$ccdir/pending.err")"
has "control centre pending says it can't be checked" "MANUAL: Can't check this automatically" "$cc_pending"
cc_open="$(printf 's\n' | PATH="$ccdir/bin:$PATH" NO_COLOR=1 MANUAL_STEPS_OPEN_TTY=1 \
  MANUAL_STEPS_LIST="$ccdir/cc.list" "$MS" open 2>"$ccdir/open.err")"
has "control centre open says it can't be checked" "MANUAL: Can't check this automatically" "$cc_open"
has "control centre open has nothing to open" "(nothing to open)" "$cc_open"
rm -rf "$ccdir"

# safari: opens in Safari, not the default browser. No real step uses it.
# The opener stays for a page that has to be added from Safari.
safari_dir="$(mktemp -d)"
safari_bin="$safari_dir/bin"
mkdir -p "$safari_bin"
cat > "$safari_bin/open" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${OPEN_LOG:?}"
exit 0
EOF
chmod +x "$safari_bin/open"
printf '%s\n' \
  'sample-safari|Apps not in the Brewfile|Open a page in Safari|Open Safari|safari:https://example.com|' \
  > "$safari_dir/steps.list"
: > "$safari_dir/open.log"
printf '\n' | PATH="$safari_bin:$PATH" NO_COLOR=1 \
  OPEN_LOG="$safari_dir/open.log" MANUAL_STEPS_OPEN_TTY=1 \
  MANUAL_STEPS_LIST="$safari_dir/steps.list" "$MS" open >/dev/null
eq "walk-through opens the page in Safari" "-a Safari https://example.com" \
  "$(cat "$safari_dir/open.log")"
rm -rf "$safari_dir"
miss "notifications-reviewed does not hard-code a Safari web app id" "Safari.WebApp." \
  "$(grep -v '^[[:space:]]*#' "$DIR/../lib/notifications-reviewed.list" || true)"

# Grok Bot Screen Recording and Accessibility sit immediately after Full Disk
# Access. The service name is the kTCCService suffix, same as SystemPolicyAllFiles.
# Both services live in the system TCC.db, which is the database check_tcc reads.
row_of() { awk -F'|' -v id="$1" '$1 == id { print; exit }' "$LIST"; }
eq "screen recording follows full disk access" "grokbot-screen-recording" \
  "$(awk -F'|' '
    $0 ~ /^[[:space:]]*#/ || $0 ~ /^[[:space:]]*$/ { next }
    prev == "grokbot-fda" { print $1; exit }
    { prev = $1 }
  ' "$LIST")"
eq "accessibility follows screen recording" "grokbot-accessibility" \
  "$(awk -F'|' '
    $0 ~ /^[[:space:]]*#/ || $0 ~ /^[[:space:]]*$/ { next }
    prev == "grokbot-screen-recording" { print $1; exit }
    { prev = $1 }
  ' "$LIST")"
screen_row="$(row_of grokbot-screen-recording)"
ax_row="$(row_of grokbot-accessibility)"
eq "screen recording title" "Give Grok Bot Computer Use Screen Recording" \
  "$(printf '%s\n' "$screen_row" | cut -d'|' -f3)"
eq "screen recording where" \
  "Open Grok Bot Computer Use first. System Settings → Privacy & Security → Screen & System Audio Recording → Grok Bot Computer Use (or accept the prompt when Grok Bot Computer Use asks). Lets Grok Bot Computer Use see the screen to do or verify GUI-only setup steps." \
  "$(printf '%s\n' "$screen_row" | cut -d'|' -f4)"
eq "screen recording opens ScreenCapture" \
  "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" \
  "$(printf '%s\n' "$screen_row" | cut -d'|' -f5)"
eq "screen recording checks Grok Bot Computer Use" \
  "tcc:ScreenCapture:co.anysphere.grok-bot-computer-use" \
  "$(printf '%s\n' "$screen_row" | cut -d'|' -f6)"
eq "accessibility title" "Give Grok Bot Computer Use Accessibility" \
  "$(printf '%s\n' "$ax_row" | cut -d'|' -f3)"
eq "accessibility where" \
  "System Settings → Privacy & Security → Accessibility → Grok Bot Computer Use. Lets Grok Bot Computer Use click and type in Mac apps." \
  "$(printf '%s\n' "$ax_row" | cut -d'|' -f4)"
eq "accessibility opens Accessibility" \
  "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" \
  "$(printf '%s\n' "$ax_row" | cut -d'|' -f5)"
eq "accessibility checks Grok Bot Computer Use" \
  "tcc:Accessibility:co.anysphere.grok-bot-computer-use" \
  "$(printf '%s\n' "$ax_row" | cut -d'|' -f6)"
eq "full disk access stays on Grok Bot" \
  "tcc:SystemPolicyAllFiles:com.anysphere.sand" \
  "$(row_of grokbot-fda | cut -d'|' -f6)"
# shellcheck disable=SC2016  # the default assignment is compared literally
has "tcc check reads the system database" \
  'TCC_DB="${MANUAL_STEPS_TCC_DB:-/Library/Application Support/com.apple.TCC/TCC.db}"' \
  "$(cat "$MS")"
has "checker names ScreenCapture as a system service" "kTCCServiceScreenCapture" "$(cat "$MS")"
has "checker names Accessibility as a system service" "kTCCServiceAccessibility" "$(cat "$MS")"
# shellcheck disable=SC2016  # the user-database path is compared literally
miss "tcc check does not default to the user database" \
  '$HOME/Library/Application Support/com.apple.TCC/TCC.db' "$(cat "$MS")"
has "manual-steps policy keeps by-hand GUI steps" \
  "GUI steps may be done or verified by Grok Bot computer use, but every such step keeps its by-hand instructions in \`lib/manual-steps.list\`, because Grok Bot isn't always available; Grok Bot computer use cannot drive System Settings, terminals, password apps, or Cursor/Grok Bot themselves." \
  "$(cat "$DIR/../AGENTS.md")"
# shellcheck disable=SC2016  # needles are markdown, compared literally
has "settings names Grok Bot Screen Recording" 'manual step `grokbot-screen-recording`' "$settings"
# shellcheck disable=SC2016  # needles are markdown, compared literally
has "settings names Grok Bot Accessibility" 'manual step `grokbot-accessibility`' "$settings"
has "settings says both grants are in the system TCC database" \
  "The per-user TCC database does not hold those services." "$settings"
has "settings names the Computer Use bundle" "co.anysphere.grok-bot-computer-use" "$settings"

# A stub sqlite3 records the query. The real script's default database is the
# system TCC.db; this does not open that file and does not grant anything.
tccdir="$(mktemp -d)"
mkdir -p "$tccdir/bin"
cat > "$tccdir/bin/sqlite3" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${TCC_SQLITE_LOG:?}"
sql=""
for arg in "$@"; do
  case "$arg" in
    SELECT*) sql="$arg" ;;
  esac
done
case "$sql" in
  *kTCCServiceScreenCapture*) val="${TCC_SCREEN-}" ;;
  *kTCCServiceAccessibility*) val="${TCC_AX-}" ;;
  *) val="" ;;
esac
if [ "${TCC_SQLITE_RC:-0}" -ne 0 ]; then
  exit "$TCC_SQLITE_RC"
fi
printf '%s\n' "$val"
exit 0
EOF
chmod +x "$tccdir/bin/sqlite3"
printf '%s\n' \
  'grokbot-screen-recording|Privacy & Security permissions|Give Grok Bot Computer Use Screen Recording|Where|x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture|tcc:ScreenCapture:co.anysphere.grok-bot-computer-use' \
  'grokbot-accessibility|Privacy & Security permissions|Give Grok Bot Computer Use Accessibility|Where|x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility|tcc:Accessibility:co.anysphere.grok-bot-computer-use' \
  > "$tccdir/steps.list"
: > "$tccdir/sqlite.log"
tcc_check() {
  TCC_SCREEN="$1" TCC_AX="$2" TCC_SQLITE_RC="${3:-0}" \
    TCC_SQLITE_LOG="$tccdir/sqlite.log" \
    PATH="$tccdir/bin:$PATH" NO_COLOR=1 \
    MANUAL_STEPS_LIST="$tccdir/steps.list" \
    "$MS" check --porcelain 2>"$tccdir/err"
}
tcc_status() { printf '%s\n' "$1" | awk -F'|' -v id="$2" '$3 == id { print $1; exit }'; }
tcc_detail() { printf '%s\n' "$1" | awk -F'|' -v id="$2" '$3 == id { print $5; exit }'; }
tcc_out="$(tcc_check 2 2)"
tcc_rc=$?
eq "granted screen recording and accessibility exit 0" 0 "$tcc_rc"
eq "screen recording auth 2 is allowed" ok "$(tcc_status "$tcc_out" grokbot-screen-recording)"
eq "accessibility auth 2 is allowed" ok "$(tcc_status "$tcc_out" grokbot-accessibility)"
has "screen recording query uses the system database" \
  "-readonly /Library/Application Support/com.apple.TCC/TCC.db SELECT auth_value FROM access WHERE service='kTCCServiceScreenCapture' AND client='co.anysphere.grok-bot-computer-use' AND client_type=0 LIMIT 1;" \
  "$(cat "$tccdir/sqlite.log")"
has "accessibility query uses the system database" \
  "-readonly /Library/Application Support/com.apple.TCC/TCC.db SELECT auth_value FROM access WHERE service='kTCCServiceAccessibility' AND client='co.anysphere.grok-bot-computer-use' AND client_type=0 LIMIT 1;" \
  "$(cat "$tccdir/sqlite.log")"
miss "queries do not open the user TCC database" \
  "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
  "$(cat "$tccdir/sqlite.log")"
: > "$tccdir/sqlite.log"
tcc_out="$(tcc_check 3 0)"
eq "screen recording auth 3 is allowed" ok "$(tcc_status "$tcc_out" grokbot-screen-recording)"
eq "accessibility switched off warns" warn "$(tcc_status "$tcc_out" grokbot-accessibility)"
eq "switched off names the state" "listed but switched off" \
  "$(tcc_detail "$tcc_out" grokbot-accessibility)"
: > "$tccdir/sqlite.log"
tcc_out="$(tcc_check '' '')"
tcc_rc=$?
eq "a missing TCC row warns" 1 "$tcc_rc"
eq "missing screen recording is not in the list" "not in the list yet" \
  "$(tcc_detail "$tcc_out" grokbot-screen-recording)"
eq "missing accessibility is not in the list" "not in the list yet" \
  "$(tcc_detail "$tcc_out" grokbot-accessibility)"
tcc_out="$(tcc_check 2 2 1)"
tcc_rc=$?
eq "an unreadable TCC database is check by hand" hand \
  "$(tcc_status "$tcc_out" grokbot-screen-recording)"
eq "an unreadable TCC database does not fail the run" 0 "$tcc_rc"
has "an unreadable TCC database names Full Disk Access" \
  "needs Full Disk Access" "$(tcc_detail "$tcc_out" grokbot-accessibility)"
rm -rf "$tccdir"

printf 'manual-steps tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
