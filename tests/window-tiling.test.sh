#!/usr/bin/env bash
#
# Native window tiling plus desktop widgets and Stage Manager: the
# com.apple.WindowManager rows in lib/macos-defaults.list, an empty restart
# (no killall of Dock or WindowManager), and the Window Tiling section of
# SHORTCUTS.md.
# macos.sh is driven with a fake `defaults` and `killall` so this runs on
# Linux CI and never touches a live WindowManager. Run: ./tests/window-tiling.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="$DIR/lib/macos-defaults.list"
MACOS="$DIR/macos.sh"
SHORTCUTS="$DIR/SHORTCUTS.md"
PINS="$DIR/lib/desktop-bindings.list"
PINS_PY="$DIR/lib/desktop-bindings.py"

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

rows="$(grep -vE '^[[:space:]]*(#|$)' "$LIST")"
field() {  # domain key field-number (1-based)
  awk -F'|' -v d="$1" -v k="$2" -v f="$3" '$1 == d && $2 == k { print $f; exit }' "$LIST"
}

# ---- list rows (the single source macos.sh and macconfig-check.sh share) ----
for row in \
  'com.apple.WindowManager|EnableTilingByEdgeDrag|bool|true||Window Tiling|Drag windows to left or right edge to tile|' \
  'com.apple.WindowManager|EnableTiledWindowMargins|bool|false||Window Tiling|Tiled windows have margins|' \
  'com.apple.WindowManager|StandardHideWidgets|bool|true||Desktop|Show widgets on Desktop|' \
  'com.apple.WindowManager|StageManagerHideWidgets|bool|true||Desktop|Show widgets in Stage Manager|' \
  'com.apple.WindowManager|GloballyEnabled|bool|false||Desktop|Stage Manager|'
do
  has "defaults row $(printf '%s' "$row" | cut -d'|' -f1-2)" "$row" "$rows"
done

eq "edge drag is bool true" true "$(field com.apple.WindowManager EnableTilingByEdgeDrag 4)"
eq "margins is bool false" false "$(field com.apple.WindowManager EnableTiledWindowMargins 4)"
eq "desktop widgets hidden" true "$(field com.apple.WindowManager StandardHideWidgets 4)"
eq "stage manager widgets hidden" true "$(field com.apple.WindowManager StageManagerHideWidgets 4)"
eq "stage manager is bool false" false "$(field com.apple.WindowManager GloballyEnabled 4)"
eq "edge drag type is bool" bool "$(field com.apple.WindowManager EnableTilingByEdgeDrag 3)"
eq "margins type is bool" bool "$(field com.apple.WindowManager EnableTiledWindowMargins 3)"
eq "desktop widgets type is bool" bool "$(field com.apple.WindowManager StandardHideWidgets 3)"
eq "stage manager widgets type is bool" bool "$(field com.apple.WindowManager StageManagerHideWidgets 3)"
eq "stage manager type is bool" bool "$(field com.apple.WindowManager GloballyEnabled 3)"
eq "edge drag restart is empty" "" "$(field com.apple.WindowManager EnableTilingByEdgeDrag 5)"
eq "margins restart is empty" "" "$(field com.apple.WindowManager EnableTiledWindowMargins 5)"
eq "desktop widgets restart is empty" "" "$(field com.apple.WindowManager StandardHideWidgets 5)"
eq "stage manager widgets restart is empty" "" "$(field com.apple.WindowManager StageManagerHideWidgets 5)"
eq "stage manager restart is empty" "" "$(field com.apple.WindowManager GloballyEnabled 5)"
eq "exactly five WindowManager keys" \
  $'EnableTiledWindowMargins\nEnableTilingByEdgeDrag\nGloballyEnabled\nStageManagerHideWidgets\nStandardHideWidgets' \
  "$(awk -F'|' '$1=="com.apple.WindowManager" { print $2 }' "$LIST" | sort)"

for banned in HideDesktop EnableTopTilingByEdgeDrag EnableTilingOptionAccelerator \
  AppWindowGroupingBehavior EnableStandardClickToShowDesktop
do
  eq "list does not pin $banned" "" "$(awk -F'|' -v k="$banned" '$2 == k { print; exit }' "$LIST")"
done

has "autofix defaults row covers window tiling" "window tiling" \
  "$(awk -F'|' '$1=="defaults" { print; exit }' "$DIR/lib/autofix.list")"
has "settings names the edge-drag key" "EnableTilingByEdgeDrag" "$(cat "$DIR/docs/settings.md")"
has "settings names the margins key" "EnableTiledWindowMargins" "$(cat "$DIR/docs/settings.md")"
has "settings names desktop widgets" "StandardHideWidgets" "$(cat "$DIR/docs/settings.md")"
has "settings names stage manager widgets" "StageManagerHideWidgets" "$(cat "$DIR/docs/settings.md")"
has "settings names stage manager" "GloballyEnabled" "$(cat "$DIR/docs/settings.md")"
has "settings leaves click-to-show-desktop out" "EnableStandardClickToShowDesktop" "$(cat "$DIR/docs/settings.md")"
# shellcheck disable=SC2016  # needle is source text, compared literally
has "settings records the empty restart" 'Both rows leave `restart` empty.' "$(cat "$DIR/docs/settings.md")"
# shellcheck disable=SC2016  # needle is source text, compared literally
has "settings records widget restart empty" 'Those rows leave `restart` empty too.' "$(cat "$DIR/docs/settings.md")"

# Desktop pins and Hammerspoon stay out of this change.
miss "desktop pins do not name WindowManager" "WindowManager" "$(cat "$PINS")"
hs_hit="$(grep -n -E 'EnableTiling|com\.apple\.WindowManager' "$DIR"/hammerspoon/*.lua || true)"
eq "hammerspoon does not manage window tiling" "" "$hs_hit"

# ---- SHORTCUTS.md: Apple-documented shortcuts, no raw angle brackets ----
section="$(awk '/^#### Window Tiling$/{p=1; next} /^#### /{p=0} p' "$SHORTCUTS")"
has "shortcuts section exists" "Tile left half" "$section"
has "left half" "| Tile left half | Globe + Control + Left Arrow |" "$section"
has "right half" "| Tile right half | Globe + Control + Right Arrow |" "$section"
has "top half" "| Tile top half | Globe + Control + Up Arrow |" "$section"
has "bottom half" "| Tile bottom half | Globe + Control + Down Arrow |" "$section"
has "fill" "| Fill the desktop | Globe + Control + F |" "$section"
has "return to previous size" "| Return to previous size | Globe + Control + R |" "$section"
has "shift-left arranges two windows" \
  "| Active window left, second window right | Globe + Control + Shift + Left Arrow |" "$section"
has "shift-right arranges two windows" \
  "| Active window right, second window left | Globe + Control + Shift + Right Arrow |" "$section"
has "shift-up arranges two windows" \
  "| Active window top, second window bottom | Globe + Control + Shift + Up Arrow |" "$section"
has "shift-down arranges two windows" \
  "| Active window bottom, second window top | Globe + Control + Shift + Down Arrow |" "$section"
has "quarters have no shortcut" "quarter positions have no keyboard shortcut" "$section"
has "option-shift left is the quarter arrange" \
  "| Active window left half, second and third windows in the right quarters | Globe + Control + Option + Shift + Left Arrow |" \
  "$section"
has "drag-to-edge note" "Drag a window to a screen edge" "$section"
has "option drag tiles immediately" "Hold Option while dragging" "$section"
has "option drag says immediately" "tiles immediately" "$section"
miss "shortcuts section has no raw <" "<" "$section"
miss "shortcuts section has no raw >" ">" "$section"
miss "old unconfirmed control-option hint is gone" "⌃⌥" "$(cat "$SHORTCUTS")"

# ---- macos.sh --list ----------------------------------------------------
list_out="$("$MACOS" --list)"
# shellcheck disable=SC2016  # needles are Markdown from macos.sh --list, compared literally
has "list prints edge drag" \
  '| Window Tiling | Drag windows to left or right edge to tile | `com.apple.WindowManager EnableTilingByEdgeDrag` | `true` (On) |' \
  "$list_out"
# shellcheck disable=SC2016  # needle is Markdown from macos.sh --list, compared literally
has "list prints margins" \
  '| Window Tiling | Tiled windows have margins | `com.apple.WindowManager EnableTiledWindowMargins` | `false` (Off) |' \
  "$list_out"
# shellcheck disable=SC2016  # needle is Markdown from macos.sh --list, compared literally
has "list prints desktop widgets" \
  '| Desktop | Show widgets on Desktop | `com.apple.WindowManager StandardHideWidgets` | `true` (Off — hidden) |' \
  "$list_out"
# shellcheck disable=SC2016  # needle is Markdown from macos.sh --list, compared literally
has "list prints stage manager widgets" \
  '| Desktop | Show widgets in Stage Manager | `com.apple.WindowManager StageManagerHideWidgets` | `true` (Off — hidden) |' \
  "$list_out"
# shellcheck disable=SC2016  # needle is Markdown from macos.sh --list, compared literally
has "list prints stage manager" \
  '| Desktop | Stage Manager | `com.apple.WindowManager GloballyEnabled` | `false` (Off) |' \
  "$list_out"

# ---- macos.sh with a fake defaults / killall ----------------------------
tmp="$(mktemp -d)"
bin="$tmp/bin"
state="$tmp/state"
dlog="$tmp/defaults.log"
klog="$tmp/killall.log"
mkdir -p "$bin"
pins_before="$(cksum "$PINS" "$PINS_PY")"

BACKUP_BEFORE=""
if [ -d "$DIR/backups" ]; then
  BACKUP_BEFORE="$(find "$DIR/backups" -mindepth 1 -maxdepth 1 -type d -name 'defaults-*' | sort)"
fi
cleanup() {
  local d now
  if [ -d "$DIR/backups" ]; then
    now="$(find "$DIR/backups" -mindepth 1 -maxdepth 1 -type d -name 'defaults-*' | sort)"
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      case "$BACKUP_BEFORE" in
        *"$d"*) ;;
        *) rm -rf "$d" ;;
      esac
    done <<< "$now"
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

cat > "$bin/defaults" <<'EOF'
#!/usr/bin/env bash
# Fake `defaults`. State lines: domain|key|type|value
printf '%s\n' "$*" >> "${DEFAULTS_LOG:?}"
args=("$@")
if [ "${args[0]}" = "-currentHost" ]; then
  args=("${args[@]:1}")
fi
cmd="${args[0]}"
domain="${args[1]:-}"
key="${args[2]:-}"
case "$cmd" in
  read|read-type)
    line="$(awk -F'|' -v d="$domain" -v k="$key" '$1 == d && $2 == k { print; exit }' "${DEFAULTS_STATE:?}")"
    [ -n "$line" ] || exit 1
    if [ "$cmd" = read ]; then
      printf '%s\n' "$(printf '%s\n' "$line" | cut -d'|' -f4-)"
      exit 0
    fi
    typ="$(printf '%s\n' "$line" | cut -d'|' -f3)"
    case "$typ" in
      string) echo "Type is string" ;;
      bool)   echo "Type is boolean" ;;
      int)    echo "Type is integer" ;;
      float)  echo "Type is float" ;;
      *) exit 1 ;;
    esac
    ;;
  export)
    touch "${args[2]}"
    ;;
  write)
    printf 'W|%s|%s|%s|%s\n' "$domain" "$key" "${args[3]:-}" "${args[4]:-}" >> "${DEFAULTS_LOG:?}"
    ;;
  *)
    echo "unexpected defaults $*" >> "${DEFAULTS_LOG:?}"
    exit 1
    ;;
esac
EOF
cat > "$bin/killall" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${KILLALL_LOG:?}"
exit 0
EOF
chmod +x "$bin/defaults" "$bin/killall"

EDGE='com.apple.WindowManager|EnableTilingByEdgeDrag'
MARGINS='com.apple.WindowManager|EnableTiledWindowMargins'
: > "$state"
run_macos() {
  : > "$dlog"
  : > "$klog"
  PATH="$bin:$PATH" DEFAULTS_LOG="$dlog" DEFAULTS_STATE="$state" KILLALL_LOG="$klog" \
    "$MACOS" --no-color --yes "$@" --only "$EDGE" --only "$MARGINS"
}

writes() { grep '^W|' "$dlog" || true; }

# Unset edge drag (the system default, On) is pinned to true. Margins already
# read as boolean 0, which is the pinned false, so that key is left alone.
# Neither change restarts Dock or WindowManager.
printf 'com.apple.WindowManager|EnableTiledWindowMargins|bool|0\n' > "$state"
out="$(run_macos)"
rc=$?
eq "pin unset edge drag exits 0" 0 "$rc"
has "unset edge drag is set true" \
  "com.apple.WindowManager EnableTilingByEdgeDrag — set (was unset) -> true" "$out"
has "boolean 0 margins are already false" \
  "com.apple.WindowManager EnableTiledWindowMargins — already set: 0 (left alone)" "$out"
eq "only the edge-drag key is written" \
  "W|com.apple.WindowManager|EnableTilingByEdgeDrag|-bool|true" "$(writes)"
eq "matching margins are not rewritten" "" "$(writes | grep EnableTiledWindowMargins || true)"
eq "no killall when pinning the unset default" "" "$(cat "$klog")"
miss "no Dock restart" "Restarting to apply" "$out"
miss "output does not name killall WindowManager" "WindowManager" "$(cat "$klog")"

# Dry-run writes nothing and restarts nothing.
out="$(run_macos --dry-run)"
rc=$?
eq "dry-run exits 0" 0 "$rc"
has "dry-run would set edge drag" \
  "com.apple.WindowManager EnableTilingByEdgeDrag — would set (was unset) -> true" "$out"
eq "dry-run does not write" "" "$(writes)"
eq "dry-run does not restart" "" "$(cat "$klog")"

# Both keys already match (defaults read prints 1 for boolean true).
printf 'com.apple.WindowManager|EnableTilingByEdgeDrag|bool|1\ncom.apple.WindowManager|EnableTiledWindowMargins|bool|0\n' > "$state"
out="$(run_macos)"
rc=$?
eq "already-set exits 0" 0 "$rc"
has "edge drag 1 is already true" \
  "com.apple.WindowManager EnableTilingByEdgeDrag — already set: 1 (left alone)" "$out"
eq "already-set writes nothing" "" "$(writes)"
eq "already-set restarts nothing" "" "$(cat "$klog")"

# Drift: margins On (1) is repaired to false, still with no process restart.
printf 'com.apple.WindowManager|EnableTilingByEdgeDrag|bool|true\ncom.apple.WindowManager|EnableTiledWindowMargins|bool|1\n' > "$state"
out="$(run_macos)"
rc=$?
eq "margins drift exits 0" 0 "$rc"
has "margins change 1 to false" \
  "com.apple.WindowManager EnableTiledWindowMargins — changed: 1 -> false" "$out"
eq "margins write is -bool false" \
  "W|com.apple.WindowManager|EnableTiledWindowMargins|-bool|false" "$(writes)"
eq "margins repair restarts nothing" "" "$(cat "$klog")"
miss "margins repair does not restart Dock" "Dock" "$(cat "$klog")"

# A wrong stored type is skipped, never clobbered.
printf 'com.apple.WindowManager|EnableTiledWindowMargins|int|0\n' > "$state"
out="$(run_macos)"
rc=$?
eq "type mismatch still exits 0" 0 "$rc"
has "integer 0 is a type mismatch" \
  "com.apple.WindowManager EnableTiledWindowMargins — type mismatch (expected boolean, found integer); skipping" "$out"
eq "type mismatch writes no margins value" "" "$(writes | grep EnableTiledWindowMargins || true)"
eq "type mismatch restarts nothing" "" "$(cat "$klog")"

# Hidden widgets and Stage Manager off are repaired with no process restart.
# Boolean 0 is widgets showing. Boolean 1 is Stage Manager on.
HIDE='com.apple.WindowManager|StandardHideWidgets'
SMHIDE='com.apple.WindowManager|StageManagerHideWidgets'
STAGE='com.apple.WindowManager|GloballyEnabled'
printf 'com.apple.WindowManager|StandardHideWidgets|bool|0\ncom.apple.WindowManager|StageManagerHideWidgets|bool|0\ncom.apple.WindowManager|GloballyEnabled|bool|1\n' > "$state"
: > "$dlog"
: > "$klog"
out="$(PATH="$bin:$PATH" DEFAULTS_LOG="$dlog" DEFAULTS_STATE="$state" KILLALL_LOG="$klog" \
  "$MACOS" --no-color --yes --only "$HIDE" --only "$SMHIDE" --only "$STAGE")"
rc=$?
eq "widget and stage drift exits 0" 0 "$rc"
has "desktop widgets change 0 to true" \
  "com.apple.WindowManager StandardHideWidgets — changed: 0 -> true" "$out"
has "stage manager widgets change 0 to true" \
  "com.apple.WindowManager StageManagerHideWidgets — changed: 0 -> true" "$out"
has "stage manager changes 1 to false" \
  "com.apple.WindowManager GloballyEnabled — changed: 1 -> false" "$out"
eq "widget and stage writes" \
  $'W|com.apple.WindowManager|StandardHideWidgets|-bool|true\nW|com.apple.WindowManager|StageManagerHideWidgets|-bool|true\nW|com.apple.WindowManager|GloballyEnabled|-bool|false' \
  "$(writes)"
eq "widget and stage repair restarts nothing" "" "$(cat "$klog")"
miss "widget repair does not restart Dock" "Dock" "$(cat "$klog")"
miss "widget repair does not name killall WindowManager" "WindowManager" "$(cat "$klog")"

# Boolean 1 is already hidden. Boolean 0 is Stage Manager already off.
printf 'com.apple.WindowManager|StandardHideWidgets|bool|1\ncom.apple.WindowManager|StageManagerHideWidgets|bool|1\ncom.apple.WindowManager|GloballyEnabled|bool|0\n' > "$state"
: > "$dlog"
: > "$klog"
out="$(PATH="$bin:$PATH" DEFAULTS_LOG="$dlog" DEFAULTS_STATE="$state" KILLALL_LOG="$klog" \
  "$MACOS" --no-color --yes --only "$HIDE" --only "$SMHIDE" --only "$STAGE")"
rc=$?
eq "already-hidden widgets exit 0" 0 "$rc"
has "desktop widgets 1 are already true" \
  "com.apple.WindowManager StandardHideWidgets — already set: 1 (left alone)" "$out"
has "stage manager widgets 1 are already true" \
  "com.apple.WindowManager StageManagerHideWidgets — already set: 1 (left alone)" "$out"
has "stage manager 0 is already false" \
  "com.apple.WindowManager GloballyEnabled — already set: 0 (left alone)" "$out"
eq "already-hidden widgets write nothing" "" "$(writes)"
eq "already-off stage manager restarts nothing" "" "$(cat "$klog")"

eq "desktop pin files unchanged" "$pins_before" "$(cksum "$PINS" "$PINS_PY")"

printf 'window-tiling tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
