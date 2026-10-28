#!/usr/bin/env bash
#
# Live apply for dark mode, the trackpad, and built-in More Space.
# osascript, activateSettings, displayplacer, and system_profiler are stubs.
# Nothing here talks to a real display or System Events.
# Run: ./tests/live-apply.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hermetic.sh disable=SC1091
. "$DIR/tests/hermetic.sh"
MACOS="$DIR/macos.sh"
# shellcheck source=../lib/dotfiles-log.sh disable=SC1091
. "$DIR/lib/dotfiles-log.sh"

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

DEF="$DIR/lib/macos-defaults.list"
LIST="$DIR/lib/manual-steps.list"
has "dark mode uses the System Events command" \
  'tell application "System Events" to tell appearance preferences to set dark mode to true' \
  "$(cat "$MACOS")"
eq "dark mode does not ask for a logout" "" \
  "$(awk -F'|' '$1 == "NSGlobalDomain" && $2 == "AppleInterfaceStyle" { print $5; exit }' "$DEF")"
eq "secondary click stays the bottom-right corner" "2" \
  "$(awk -F'|' '$2 == "TrackpadCornerSecondaryClick" { print $4; exit }' "$DEF")"
eq "right-side secondary click stays off" "0" \
  "$(awk -F'|' '$2 == "TrackpadRightClick" { print $4; exit }' "$DEF")"
eq "auto-brightness is the first display step" "auto-brightness" \
  "$(awk -F'|' '$2 == "Display, keyboard & desktop" { print $1; exit }' "$LIST")"
eq "auto-brightness opens Displays" "x-apple.systempreferences:com.apple.Displays-Settings.extension" \
  "$(awk -F'|' '$1 == "auto-brightness" { print $5; exit }' "$LIST")"
has "wallpaper step says there is no reliable command" "no reliable command" \
  "$(awk -F'|' '$1 == "wallpaper" { print $3; exit }' "$LIST")"
eq "wallpaper stays report-only" "PAUL" \
  "$(awk -F'|' '$1 == "wallpaper" { print $2; exit }' "$DIR/lib/autofix.list")"
miss "macos.sh does not set the desktop picture" "set picture" "$(cat "$MACOS")"
has "bootstrap names auto-brightness before the checklist" \
  "Still by hand: Automatically adjust brightness Off" "$(cat "$DIR/bootstrap.sh")"
has "bootstrap logout notice is the helper" "dotfiles_print_logout_notice" "$(cat "$DIR/bootstrap.sh")"
order="$(awk '
  /Still by hand: Automatically adjust brightness Off/ { b = NR }
  /"\$MANUAL_STEPS" pending/ { l = NR }
  /dotfiles_print_logout_notice/ { n = NR }
  END { if (b && l && n && b < l && l < n) print "ok"; else print "bad" }
' "$DIR/bootstrap.sh")"
eq "brightness note, then the checklist, then the logout notice" "ok" "$order"

tmp="$(mktemp -d)"
bin="$tmp/bin"
state="$tmp/state"
dlog="$tmp/defaults.log"
olog="$tmp/osascript.log"
alog="$tmp/activate.log"
plog="$tmp/profiler.log"
placerlog="$tmp/displayplacer.log"
placerstate="$tmp/displayplacer.state"
logout="$tmp/logout.txt"
mkdir -p "$bin"
: > "$state"
: > "$dlog"
: > "$olog"
: > "$alog"
: > "$plog"
: > "$placerlog"

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
  export) touch "${args[2]}" ;;
  write)
    printf 'W|%s|%s|%s|%s\n' "$domain" "$key" "${args[3]:-}" "${args[4]:-}" >> "${DEFAULTS_LOG:?}"
    ;;
  *) exit 1 ;;
esac
EOF
cat > "$bin/osascript" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${OSASCRIPT_LOG:?}"
case "$*" in
  *'get dark mode'*)
    case "${OSASCRIPT_GET:-true}" in
      fail) exit 1 ;;
      *) printf '%s\n' "$OSASCRIPT_GET" ;;
    esac
    ;;
  *'set dark mode to true'*)
    case "${OSASCRIPT_SET:-ok}" in
      fail) echo "automation denied" >&2; exit 1 ;;
      *) exit 0 ;;
    esac
    ;;
  *) echo "unexpected osascript $*" >&2; exit 1 ;;
esac
EOF
cat > "$bin/activateSettings" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${ACTIVATE_LOG:?}"
exit "${ACTIVATE_RC:-0}"
EOF
cat > "$bin/system_profiler" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${PROFILER_LOG:?}"
if [ "${1:-}" = "SPDisplaysDataType" ]; then
  cat "${PROFILER_JSON:?}"
  exit 0
fi
exit 1
EOF
# A set that names a pinned rate (enabled:true ... hz:N) is recorded, and
# list then prints "$DISPLAYPLACER_LIST.N" when that file exists. A rate in
# DISPLAYPLACER_REFUSE_HZ is not set: it exits 1, or exits 0 and leaves the
# screen as it was when DISPLAYPLACER_REFUSE=silent. DISPLAYPLACER_LATE_LISTS=N
# keeps the old screen for the next N lists after a set, like a slow dock.
cat > "$bin/displayplacer" <<'EOF'
#!/usr/bin/env bash
printf 'CALL %s\n' "$*" >> "${DISPLAYPLACER_LOG:?}"
if [ "${1:-}" = "list" ]; then
  late="$(cat "$DISPLAYPLACER_STATE.late" 2>/dev/null || true)"
  if [ -n "$late" ] && [ "$late" -gt 0 ]; then
    printf '%s\n' "$((late - 1))" > "$DISPLAYPLACER_STATE.late"
    cat "$DISPLAYPLACER_STATE.before" 2>/dev/null || true
    exit 0
  fi
  now="$(cat "${DISPLAYPLACER_STATE:?}" 2>/dev/null || true)"
  if [ -n "$now" ] && [ -f "${DISPLAYPLACER_LIST:?}.$now" ]; then
    cat "$DISPLAYPLACER_LIST.$now"
  else
    cat "${DISPLAYPLACER_LIST:?}"
  fi
  exit 0
fi
hz=""
for arg in "$@"; do
  case "$arg" in
    *enabled:true*) hz="${arg#* hz:}"; hz="${hz%% *}" ;;
  esac
done
if [ -n "$hz" ]; then
  case " ${DISPLAYPLACER_REFUSE_HZ:-} " in
    *" $hz "*)
      [ "${DISPLAYPLACER_REFUSE:-fail}" = silent ] && exit 0
      exit 1
      ;;
  esac
  if [ "${DISPLAYPLACER_LATE_LISTS:-0}" -gt 0 ]; then
    "$0" list > "$DISPLAYPLACER_STATE.before"
    printf '%s\n' "$DISPLAYPLACER_LATE_LISTS" > "$DISPLAYPLACER_STATE.late"
  fi
  printf '%s\n' "$hz" > "$DISPLAYPLACER_STATE"
fi
exit "${DISPLAYPLACER_RC:-0}"
EOF
cat > "$bin/killall" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$bin/defaults" "$bin/osascript" "$bin/activateSettings" "$bin/system_profiler" "$bin/displayplacer" "$bin/killall"

cat > "$tmp/not-more-space.json" <<'EOF'
{"SPDisplaysDataType":[{"spdisplays_ndrvs":[
  {"_name":"Color LCD","spdisplays_connection_type":"spdisplays_internal","_spdisplays_resolution":"1512 x 982 @ 120.00Hz","spdisplays_pixelresolution":"spdisplays_3024x1964Retina"},
  {"_name":"DELL U2723QE","spdisplays_connection_type":"spdisplays_connection_type_displayport","_spdisplays_resolution":"2560 x 1440 @ 60.00Hz"}
]}]}
EOF
cat > "$tmp/more-space.json" <<'EOF'
{"SPDisplaysDataType":[{"spdisplays_ndrvs":[
  {"_name":"Color LCD","spdisplays_connection_type":"spdisplays_internal","_spdisplays_resolution":"1800 x 1169 @ 120.00Hz","spdisplays_pixelresolution":"spdisplays_3024x1964Retina"},
  {"_name":"DELL U2723QE","spdisplays_connection_type":"spdisplays_connection_type_displayport","_spdisplays_resolution":"2560 x 1440 @ 60.00Hz"}
]}]}
EOF
cat > "$tmp/clamshell.json" <<'EOF'
{"SPDisplaysDataType":[{"spdisplays_ndrvs":[
  {"_name":"DELL U2723QE","spdisplays_connection_type":"spdisplays_connection_type_displayport","_spdisplays_resolution":"2560 x 1440 @ 60.00Hz"}
]}]}
EOF
cat > "$tmp/placer.txt" <<'EOF'
Persistent screen id: BUILTIN-ID
Type: MacBook built in screen
Resolution: 1512x982
Hertz: 120
Color Depth: 8
Scaling: on
Origin: (0,0) - main display
Rotation: 0
Resolutions for rotation 0:
  mode 0: res:1512x982 hz:120 color_depth:8 scaling:on <-- current mode
  mode 2: res:1800x1169 hz:120 color_depth:8 scaling:on

Persistent screen id: EXTERNAL-ID
Type: 27 inch external screen
Resolution: 2560x1440
Hertz: 60
Color Depth: 8
Scaling: off
Origin: (1800,0)
Rotation: 0
Resolutions for rotation 0:
  mode 0: res:2560x1440 hz:60 color_depth:8 <-- current mode
EOF
cat > "$tmp/placer-no-mode.txt" <<'EOF'
Persistent screen id: BUILTIN-ID
Type: MacBook built in screen
Resolution: 1512x982
Hertz: 120
Color Depth: 8
Scaling: on
Origin: (0,0)
Rotation: 0
Resolutions for rotation 0:
  mode 0: res:1512x982 hz:120 color_depth:8 scaling:on <-- current mode
EOF

# Stub directory first, then ordinary Unix tools only. The host PATH is not
# used: a Homebrew displayplacer there would run when the stub is hidden,
# and /usr/bin/defaults would run when the defaults stub is hidden.
BASE_PATH="$(hermetic_safe_root)"
DARK='NSGlobalDomain|AppleInterfaceStyle'
TRACK='com.apple.AppleMultitouchTrackpad|TrackpadCornerSecondaryClick'
SPACES='com.apple.spaces|spans-displays'

run_macos() {
  : > "$dlog"
  : > "$olog"
  : > "$alog"
  : > "$plog"
  : > "$placerlog"
  : > "$placerstate"
  rm -f "$placerstate.late" "$placerstate.before"
  : > "$logout"
  PATH="$bin:$BASE_PATH" \
    DEFAULTS_LOG="$dlog" DEFAULTS_STATE="$state" \
    OSASCRIPT_LOG="$olog" OSASCRIPT_GET="${OSASCRIPT_GET:-true}" OSASCRIPT_SET="${OSASCRIPT_SET:-ok}" \
    ACTIVATE_LOG="$alog" ACTIVATE_RC="${ACTIVATE_RC:-0}" \
    PROFILER_LOG="$plog" PROFILER_JSON="${PROFILER_JSON:-$tmp/not-more-space.json}" \
    DISPLAYPLACER_LOG="$placerlog" DISPLAYPLACER_LIST="${DISPLAYPLACER_LIST:-$tmp/placer.txt}" \
    DISPLAYPLACER_RC="${DISPLAYPLACER_RC:-0}" DISPLAYPLACER_STATE="$placerstate" \
    DISPLAYPLACER_REFUSE_HZ="${DISPLAYPLACER_REFUSE_HZ:-}" DISPLAYPLACER_REFUSE="${DISPLAYPLACER_REFUSE:-fail}" \
    DISPLAYPLACER_SETTLE_SECONDS=0 DISPLAYPLACER_LATE_LISTS="${DISPLAYPLACER_LATE_LISTS:-0}" \
    DOTFILES_ACTIVATE_SETTINGS="${DOTFILES_ACTIVATE_SETTINGS:-$bin/activateSettings}" \
    DOTFILES_LOGOUT_FILE="$logout" \
    "$MACOS" --no-color --yes "$@"
}

writes() { grep '^W|' "$dlog" || true; }
sets() { grep 'set dark mode to true' "$olog" || true; }

# ---- dark mode ----------------------------------------------------------
: > "$state"
OSASCRIPT_GET=false OSASCRIPT_SET=ok
out="$(run_macos --only "$DARK")"
rc=$?
eq "light appearance exits 0" 0 "$rc"
has "light appearance is turned on" "dark mode turned on (System Events)" "$out"
has "light appearance writes the default" "W|NSGlobalDomain|AppleInterfaceStyle|-string|Dark" "$(writes)"
has "light appearance calls the set command" "set dark mode to true" "$(sets)"
miss "dark mode does not ask for a logout" "AppleInterfaceStyle" "$(cat "$logout")"

printf 'NSGlobalDomain|AppleInterfaceStyle|string|Dark\n' > "$state"
OSASCRIPT_GET=true
out="$(run_macos --only "$DARK")"
rc=$?
eq "already dark exits 0" 0 "$rc"
has "already dark is left alone" "dark mode already on" "$out"
eq "already dark does not set it again" "" "$(sets)"
eq "already dark does not rewrite the default" "" "$(writes)"

: > "$state"
OSASCRIPT_GET=false OSASCRIPT_SET=fail
out="$(run_macos --only "$DARK")"
rc=$?
eq "a refused System Events call still exits 0" 0 "$rc"
has "a refused set warns about Automation permission" "missing Automation permission" "$out"
has "a refused set still writes the default" "AppleInterfaceStyle|-string|Dark" "$(writes)"

OSASCRIPT_GET=fail OSASCRIPT_SET=ok
out="$(run_macos --only "$DARK")"
rc=$?
eq "an unreadable appearance still exits 0" 0 "$rc"
has "an unreadable appearance warns" "could not read dark mode" "$out"
eq "an unreadable appearance does not set dark mode" "" "$(sets)"

OSASCRIPT_GET=false OSASCRIPT_SET=ok
out="$(run_macos --dry-run --only "$DARK")"
has "dry-run would turn dark mode on" "would turn dark mode on now" "$out"
eq "dry-run does not call set" "" "$(sets)"

# Default already Dark, but the menu bar is still light: still apply live.
printf 'NSGlobalDomain|AppleInterfaceStyle|string|Dark\n' > "$state"
OSASCRIPT_GET=false OSASCRIPT_SET=ok
out="$(run_macos --only "$DARK")"
has "a light menu bar is turned on even when the default is already Dark" \
  "dark mode turned on (System Events)" "$out"
eq "that path does not rewrite the default" "" "$(writes)"
has "that path calls set" "set dark mode to true" "$(sets)"

# ---- trackpad -----------------------------------------------------------
: > "$state"
OSASCRIPT_GET=true
ACTIVATE_RC=0
DOTFILES_ACTIVATE_SETTINGS="$bin/activateSettings"
out="$(run_macos --only "$TRACK" --only "$SPACES")"
rc=$?
eq "trackpad plus a logout setting exits 0" 0 "$rc"
eq "activateSettings is run once with -u" "-u" "$(cat "$alog")"
has "the other logout item is queued for bootstrap" "spans-displays" "$(cat "$logout")"
miss "trackpad key is not queued for bootstrap" "TrackpadCornerSecondaryClick" "$(cat "$logout")"
has "the other logout item is still named" "spans-displays" "$out"
notice="$(DOTFILES_LOGOUT_FILE="$logout" dotfiles_print_logout_notice)"
has "bootstrap notice names what still needs a logout" \
  "Log out and back in now to finish applying:" "$notice"
has "bootstrap notice lists the remaining item" "spans-displays" "$notice"
miss "bootstrap notice does not list the trackpad" "TrackpadCornerSecondaryClick" "$notice"

printf 'com.apple.AppleMultitouchTrackpad|TrackpadCornerSecondaryClick|int|2\n' > "$state"
out="$(run_macos --only "$TRACK")"
eq "an unchanged trackpad does not reload settings" "" "$(cat "$alog")"
eq "an unchanged trackpad needs no logout" "" "$(cat "$logout")"
has "an unchanged trackpad is left alone" "already set: 2 (left alone)" "$out"

: > "$state"
DOTFILES_ACTIVATE_SETTINGS="$tmp/missing-activate"
out="$(run_macos --only "$TRACK")"
has "a missing activateSettings warns" "activateSettings is not available" "$out"
has "a missing activateSettings keeps the logout item" "TrackpadCornerSecondaryClick" "$(cat "$logout")"

DOTFILES_ACTIVATE_SETTINGS="$bin/activateSettings"
ACTIVATE_RC=1
out="$(run_macos --only "$TRACK")"
rc=$?
eq "a failing activateSettings still exits 0" 0 "$rc"
has "a failing activateSettings warns" "activateSettings -u failed" "$out"
has "a failing activateSettings keeps the logout item" "TrackpadCornerSecondaryClick" "$(cat "$logout")"
ACTIVATE_RC=0

# The four keys a fresh Mac stores as booleans. Desired values are unchanged
# (int 0/1). A matching boolean is not a type mismatch. A different boolean
# is written with -bool, not -int.
printf '%s\n' \
  'com.apple.driver.AppleBluetoothMultitouch.trackpad|Clicking|bool|1' \
  'com.apple.AppleMultitouchTrackpad|Clicking|bool|1' \
  'com.apple.AppleMultitouchTrackpad|TrackpadRightClick|bool|0' \
  'com.apple.AppleMultitouchTrackpad|TrackpadThreeFingerDrag|bool|0' \
  'com.apple.AppleMultitouchTrackpad|ForceSuppressed|bool|0' \
  > "$state"
DOTFILES_ACTIVATE_SETTINGS="$bin/activateSettings"
ACTIVATE_RC=0
out="$(run_macos \
  --only 'com.apple.driver.AppleBluetoothMultitouch.trackpad|Clicking' \
  --only 'com.apple.AppleMultitouchTrackpad|Clicking' \
  --only 'com.apple.AppleMultitouchTrackpad|TrackpadRightClick' \
  --only 'com.apple.AppleMultitouchTrackpad|TrackpadThreeFingerDrag' \
  --only 'com.apple.AppleMultitouchTrackpad|ForceSuppressed')"
rc=$?
eq "boolean trackpad matches exit 0" 0 "$rc"
has "boolean tap to click matches" \
  "com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking — already set: 1 (left alone)" "$out"
has "boolean right click off matches" \
  "com.apple.AppleMultitouchTrackpad TrackpadRightClick — already set: 0 (left alone)" "$out"
has "boolean three-finger drag off matches" \
  "com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag — already set: 0 (left alone)" "$out"
has "boolean haptics on matches" \
  "com.apple.AppleMultitouchTrackpad ForceSuppressed — already set: 0 (left alone)" "$out"
miss "matching booleans are not a type mismatch" "type mismatch" "$out"
eq "matching booleans are not rewritten" "" "$(writes)"
eq "matching booleans do not reload settings" "" "$(cat "$alog")"

printf 'com.apple.AppleMultitouchTrackpad|TrackpadRightClick|bool|1\n' > "$state"
out="$(run_macos --only 'com.apple.AppleMultitouchTrackpad|TrackpadRightClick')"
rc=$?
eq "boolean right click on exits 0" 0 "$rc"
has "boolean right click on is changed" \
  "com.apple.AppleMultitouchTrackpad TrackpadRightClick — changed: 1 -> 0" "$out"
miss "a boolean that needs changing is not a type mismatch" "type mismatch" "$out"
eq "a boolean that needs changing is written with -bool" \
  "W|com.apple.AppleMultitouchTrackpad|TrackpadRightClick|-bool|false" "$(writes)"
eq "a changed boolean trackpad reloads settings" "-u" "$(cat "$alog")"

run_defaults_check() {
  HOME="$tmp/check-home" DOTDIR="$DIR" PATH="$bin:$BASE_PATH" \
    DEFAULTS_LOG="$dlog" DEFAULTS_STATE="$state" \
    bash -c '
      set -uo pipefail
      hdr() { :; }
      fixid() { :; }
      pass() { printf "PASS %s\n" "$1"; }
      bad() { printf "BAD %s\n" "$1"; }
      warn() { printf "WARN %s\n" "$1"; }
      CHECKED=0
      # shellcheck disable=SC1091
      . "$1/lib/defaults-lib.sh"
      # shellcheck disable=SC1091
      . "$1/checks/defaults.sh"
    ' bash "$DIR"
}
mkdir -p "$tmp/check-home"
printf '%s\n' \
  'com.apple.driver.AppleBluetoothMultitouch.trackpad|Clicking|bool|1' \
  'com.apple.AppleMultitouchTrackpad|Clicking|bool|1' \
  'com.apple.AppleMultitouchTrackpad|TrackpadRightClick|bool|0' \
  'com.apple.AppleMultitouchTrackpad|TrackpadThreeFingerDrag|bool|0' \
  'com.apple.AppleMultitouchTrackpad|ForceSuppressed|bool|0' \
  > "$state"
check="$(run_defaults_check)"
has "check passes boolean tap to click" \
  "PASS com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking = 1" "$check"
has "check passes boolean right click off" \
  "PASS com.apple.AppleMultitouchTrackpad TrackpadRightClick = 0" "$check"
has "check passes boolean three-finger drag off" \
  "PASS com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag = 0" "$check"
has "check passes boolean haptics on" \
  "PASS com.apple.AppleMultitouchTrackpad ForceSuppressed = 0" "$check"
miss "check does not call a matching boolean a type mismatch" \
  "Clicking — type mismatch" "$check"
miss "check does not call right click a type mismatch" \
  "TrackpadRightClick — type mismatch" "$check"

printf 'com.apple.AppleMultitouchTrackpad|TrackpadRightClick|bool|1\n' > "$state"
check="$(run_defaults_check)"
has "check names a boolean that needs changing" \
  "BAD com.apple.AppleMultitouchTrackpad TrackpadRightClick = 1 (expected 0)" "$check"
miss "check does not call that difference a type mismatch" \
  "TrackpadRightClick — type mismatch" "$check"

# ---- More Space ---------------------------------------------------------
PROFILER_JSON="$tmp/not-more-space.json"
DISPLAYPLACER_LIST="$tmp/placer.txt"
DISPLAYPLACER_RC=0
out="$(run_macos --only @display-more-space)"
rc=$?
eq "More Space apply exits 0" 0 "$rc"
has "More Space apply says it set the built-in display" "built-in display set to More Space" "$out"
has "More Space apply lists the screens first" "CALL list" "$(cat "$placerlog")"
has "More Space apply uses the built-in mode" \
  "id:BUILTIN-ID mode:2 origin:(0,0) degree:0" "$(cat "$placerlog")"
has "More Space apply repeats the external display unchanged" \
  "id:EXTERNAL-ID mode:0 origin:(1800,0) degree:0" "$(cat "$placerlog")"
miss "More Space apply does not set an external resolution" "res:1800" "$(cat "$placerlog")"

PROFILER_JSON="$tmp/more-space.json"
out="$(run_macos --only @display-more-space)"
has "already More Space is skipped" "Built-in display is More Space" "$out"
eq "already More Space does not run displayplacer" "" "$(cat "$placerlog")"

PROFILER_JSON="$tmp/clamshell.json"
out="$(run_macos --only @display-more-space)"
has "a clamshell is skipped" "no built-in display" "$out"
eq "a clamshell does not run displayplacer" "" "$(cat "$placerlog")"

PROFILER_JSON="$tmp/not-more-space.json"
DISPLAYPLACER_LIST="$tmp/placer-no-mode.txt"
out="$(run_macos --only @display-more-space)"
rc=$?
eq "a missing mode still exits 0" 0 "$rc"
has "a missing mode warns and names the manual step" "set it by hand" "$out"
has "a missing mode still reads displayplacer list" "CALL list" "$(cat "$placerlog")"
miss "a missing mode does not set a screen" "CALL id:" "$(cat "$placerlog")"

DISPLAYPLACER_LIST="$tmp/placer.txt"
DISPLAYPLACER_RC=1
out="$(run_macos --only @display-more-space)"
rc=$?
eq "a failing displayplacer still exits 0" 0 "$rc"
has "a failing displayplacer warns" "displayplacer failed" "$out"
DISPLAYPLACER_RC=0

# Hide the stub. PATH has no Homebrew bin, so command -v must miss it
# instead of running a displayplacer already installed on this Mac.
mv "$bin/displayplacer" "$bin/displayplacer.off"
found="$(PATH="$bin:$BASE_PATH" command -v displayplacer || true)"
eq "hiding the stub leaves no displayplacer on PATH" "" "$found"
out="$(run_macos --only @display-more-space)"
rc=$?
eq "a missing displayplacer still exits 0" 0 "$rc"
has "a missing displayplacer names brewsync" "brewsync" "$out"
has "a missing displayplacer points at Displays" "System Settings → Displays" "$out"
mv "$bin/displayplacer.off" "$bin/displayplacer"

PROFILER_JSON="$tmp/not-more-space.json"
out="$(run_macos --dry-run --only @display-more-space)"
has "dry-run would set More Space" "would be set to More Space" "$out"
has "dry-run still reads the mode list" "CALL list" "$(cat "$placerlog")"
miss "dry-run does not set the mode" "CALL id:" "$(cat "$placerlog")"

# ARZOPA connected, built-in already More Space, monitor on the wrong mode.
# --only @arzopa-display pins it and keeps the laptop at (0,0).
cat > "$tmp/arzopa.json" <<'EOF'
{"SPDisplaysDataType":[{"spdisplays_ndrvs":[
  {"_name":"Color LCD","spdisplays_connection_type":"spdisplays_internal","_spdisplays_resolution":"1800 x 1169 @ 120.00Hz","spdisplays_pixelresolution":"spdisplays_3024x1964Retina"},
  {"_name":"ARZOPA","spdisplays_connection_type":"spdisplays_connection_type_usb_type_c","_spdisplays_resolution":"2560 x 1440 @ 60.00Hz","_spdisplays_display-serial-number":"74646035"}
]}]}
EOF
cat > "$tmp/placer-arzopa.txt" <<'EOF'
Persistent screen id: BUILTIN-ID
Type: MacBook built in screen
Resolution: 1800x1169
Hertz: 120
Color Depth: 8
Scaling: on
Origin: (0,0) - main display
Rotation: 0
Resolutions for rotation 0:
  mode 2: res:1800x1169 hz:120 color_depth:8 scaling:on <-- current mode

Persistent screen id: FRESH-UUID
Serial screen id: s74646035
Type: 16 inch external screen
Resolution: 2560x1440
Hertz: 60
Color Depth: 8
Scaling: off
Origin: (1800,0)
Rotation: 0
Resolutions for rotation 0:
  mode 0: res:2560x1440 hz:60 color_depth:8 <-- current mode
  mode 9: res:1920x1080 hz:180 color_depth:8
EOF
PROFILER_JSON="$tmp/arzopa.json"
DISPLAYPLACER_LIST="$tmp/placer-arzopa.txt"
DISPLAYPLACER_RC=0
sed -e 's/^Resolution: 2560x1440/Resolution: 1920x1080/' -e 's/^Hertz: 60/Hertz: 180/' \
  -e 's/^Origin: (1800,0)/Origin: (-1920,0)/' \
  -e 's/^\(  mode 0: res:2560x1440 hz:60 color_depth:8\) <-- current mode$/\1/' \
  -e 's/^\(  mode 9: res:1920x1080 hz:180 color_depth:8\)$/\1 <-- current mode/' \
  "$tmp/placer-arzopa.txt" > "$tmp/placer-arzopa.txt.180"
out="$(run_macos --only @arzopa-display)"
rc=$?
eq "ARZOPA apply exits 0" 0 "$rc"
has "ARZOPA apply says it set the monitor" "set ARZOPA 1920x1080 at 180Hz, scaling off, left of the laptop" "$out"
has "ARZOPA apply reads the list again to see the rate took" \
  "CALL list" "$(sed -n '3p' "$placerlog")"
miss "a rate that took is not stepped down" "hz:144" "$(cat "$placerlog")"
miss "a rate that took is not a warning" "could not set" "$out"
has "ARZOPA apply uses the pinned mode and origin" \
  "id:FRESH-UUID res:1920x1080 hz:180 color_depth:8 enabled:true scaling:off origin:(-1920,0) degree:0" \
  "$(cat "$placerlog")"
has "ARZOPA apply keeps the laptop at the origin" \
  "id:BUILTIN-ID mode:2 origin:(0,0) degree:0" "$(cat "$placerlog")"
miss "ARZOPA apply does not call itself More Space" "More Space" "$out"

# Unplugged: the check is info and displayplacer is not asked to move anything.
PROFILER_JSON="$tmp/more-space.json"
out="$(run_macos --only @arzopa-display)"
has "an unplugged ARZOPA is not a failure" "ARZOPA not connected" "$out"
eq "an unplugged ARZOPA does not run displayplacer" "" "$(cat "$placerlog")"

# Already pinned: the ok line names the ARZOPA, not More Space. displayplacer
# list is read so the pin can be checked, and no mode is set.
cat > "$tmp/placer-arzopa-ok.txt" <<'EOF'
Persistent screen id: BUILTIN-ID
Type: MacBook built in screen
Resolution: 1800x1169
Hertz: 120
Color Depth: 8
Scaling: on
Origin: (0,0) - main display
Rotation: 0
Resolutions for rotation 0:
  mode 2: res:1800x1169 hz:120 color_depth:8 scaling:on <-- current mode

Persistent screen id: FRESH-UUID
Serial screen id: s74646035
Type: 16 inch external screen
Resolution: 1920x1080
Hertz: 180
Color Depth: 8
Scaling: off
Origin: (-1920,0)
Rotation: 0
Resolutions for rotation 0:
  mode 9: res:1920x1080 hz:180 color_depth:8 <-- current mode
EOF
PROFILER_JSON="$tmp/arzopa.json"
DISPLAYPLACER_LIST="$tmp/placer-arzopa-ok.txt"
out="$(run_macos --only @arzopa-display)"
has "an already pinned ARZOPA keeps its own ok line" \
  "ok    ARZOPA is 1920x1080 at 180Hz, scaling off" "$out"
has "an already pinned laptop keeps its own ok line" \
  "ok    Built-in display is More Space" "$out"
miss "an already pinned ARZOPA is not relabelled as More Space" "already More Space" "$out"
has "an already pinned ARZOPA still reads displayplacer list" "CALL list" "$(cat "$placerlog")"
miss "an already pinned ARZOPA does not set a mode" "CALL id:" "$(cat "$placerlog")"

# ---- ARZOPA through the StarTech Thunderbolt 5 dock ---------------------
# 1920x1080 unscaled is listed at 144, 120, 100 and 60Hz, and not at 180Hz.
cur() { [ "$1" = "$2" ] && printf ' <-- current mode'; return 0; }
dock_placer() { # current Hertz, ARZOPA origin
  cat <<EOF
Persistent screen id: BUILTIN-ID
Type: MacBook built in screen
Resolution: 1800x1169
Hertz: 120
Color Depth: 8
Scaling: on
Origin: (0,0) - main display
Rotation: 0
Resolutions for rotation 0:
  mode 2: res:1800x1169 hz:120 color_depth:8 scaling:on <-- current mode

Persistent screen id: DOCK-UUID
Serial screen id: s74646035
Type: 16 inch external screen
Resolution: 1920x1080
Hertz: $1
Color Depth: 8
Scaling: off
Origin: ${2:-(-1920,0)}
Rotation: 0
Resolutions for rotation 0:
  mode 0: res:1920x1080 hz:144 color_depth:8$(cur "$1" 144)
  mode 1: res:1920x1080 hz:120 color_depth:8$(cur "$1" 120)
  mode 2: res:1920x1080 hz:100 color_depth:8$(cur "$1" 100)
  mode 3: res:1920x1080 hz:60 color_depth:8$(cur "$1" 60)
EOF
}
dock_placer 144 > "$tmp/dock-144.txt"
dock_placer 100 > "$tmp/dock-100.txt"
for hz in 144 120 100 60; do
  dock_placer "$hz" > "$tmp/dock-100.txt.$hz"
done
PROFILER_JSON="$tmp/arzopa.json"

DISPLAYPLACER_LIST="$tmp/dock-144.txt"
out="$(run_macos --only @arzopa-display)"
has "the dock at 144Hz is ok" \
  "ok    ARZOPA is 1920x1080 at 144Hz, the highest this connection offers (180Hz needs a direct connection)" "$out"
miss "the dock at 144Hz does not set a mode" "CALL id:" "$(cat "$placerlog")"
has "the dock at 144Hz is not a warning" "0 warning(s)" "$out"

DISPLAYPLACER_LIST="$tmp/dock-100.txt"
out="$(run_macos --only @arzopa-display)"
rc=$?
eq "the dock at 100Hz exits 0" 0 "$rc"
has "the dock at 100Hz is set to 144Hz" "set ARZOPA 1920x1080 at 144Hz, scaling off, left of the laptop" "$out"
has "the dock set uses the 144Hz unscaled mode" \
  "id:DOCK-UUID res:1920x1080 hz:144 color_depth:8 enabled:true scaling:off origin:(-1920,0) degree:0" \
  "$(cat "$placerlog")"
miss "the dock set does not ask for 180Hz" "hz:180" "$(cat "$placerlog")"
miss "the dock set that took is not a warning" "could not set" "$out"

# A slow dock shows 144Hz only after the check after the set gave up. The
# list read for the next plan shows it, so 144Hz stays and 120Hz is not set.
DISPLAYPLACER_LATE_LISTS=3
out="$(run_macos --only @arzopa-display)"
DISPLAYPLACER_LATE_LISTS=0
has "a slow dock keeps the 144Hz that took" "set ARZOPA 1920x1080 at 144Hz, scaling off, left of the laptop" "$out"
miss "a slow dock is not stepped down to 120Hz" "hz:120" "$(cat "$placerlog")"
miss "a slow dock is not a warning" "could not set" "$out"
eq "a slow dock sets once" "1" "$(grep -c 'CALL id:' "$placerlog")"

# 144Hz fails: the next listed rate down is set, with a warning.
DISPLAYPLACER_REFUSE_HZ="144"
DISPLAYPLACER_REFUSE=fail
out="$(run_macos --only @arzopa-display)"
rc=$?
eq "a failed 144Hz set still exits 0" 0 "$rc"
has "a failed 144Hz set tries 144Hz first" "hz:144" "$(cat "$placerlog")"
has "a failed 144Hz set falls back to 120Hz" \
  "id:DOCK-UUID res:1920x1080 hz:120 color_depth:8 enabled:true scaling:off origin:(-1920,0) degree:0" \
  "$(cat "$placerlog")"
has "a failed 144Hz set says 120Hz was set" "set ARZOPA 1920x1080 at 120Hz" "$out"
has "a failed 144Hz set says which rate did not take" "ARZOPA: displayplacer could not set 144Hz, so 120Hz was used" "$out"
miss "a failed 144Hz set is not called a More Space failure" "displayplacer failed" "$out"

# displayplacer exits 0 but the rate does not take (the dock stayed on
# 100Hz while 144Hz was listed). 144Hz and 120Hz are tried, then 100Hz is
# what the connection can be set to, and it is already there.
DISPLAYPLACER_REFUSE_HZ="144 120"
DISPLAYPLACER_REFUSE=silent
out="$(run_macos --only @arzopa-display)"
rc=$?
eq "rates that do not take still exit 0" 0 "$rc"
has "rates that do not take name what was tried" "ARZOPA: displayplacer could not set 144Hz or 120Hz" "$out"
has "rates that do not take leave the ARZOPA at 100Hz" \
  "ARZOPA is 1920x1080 at 100Hz, the highest rate displayplacer could set" "$out"
eq "rates that do not take are tried once each" "2" "$(grep -c 'CALL id:' "$placerlog")"
miss "rates that do not take do not try 60Hz" "hz:60" "$(cat "$placerlog")"

# No listed rate can be set: one warning, by hand.
dock_placer 100 "(1800,0)" > "$tmp/dock-away.txt"
DISPLAYPLACER_LIST="$tmp/dock-away.txt"
DISPLAYPLACER_REFUSE_HZ="144 120 100 60"
DISPLAYPLACER_REFUSE=fail
out="$(run_macos --only @arzopa-display)"
rc=$?
eq "no settable rate still exits 0" 0 "$rc"
eq "no settable rate tries each listed rate" "4" "$(grep -c 'CALL id:' "$placerlog")"
has "no settable rate warns by hand" \
  "ARZOPA: displayplacer could not set 1920x1080 with scaling off at any listed refresh rate (144, 120, 100, 60Hz) — set it by hand" "$out"
miss "no settable rate does not claim a set" "set ARZOPA" "$out"
DISPLAYPLACER_REFUSE_HZ=""
DISPLAYPLACER_REFUSE=fail

# Real displayplacer list from Paul's Mac, ARZOPA on the dock at 144Hz.
REAL="$DIR/tests/fixtures/displayplacer-dock.txt"
cat > "$tmp/arzopa-dock.json" <<'EOF'
{"SPDisplaysDataType":[{"spdisplays_ndrvs":[
  {"_name":"Color LCD","spdisplays_connection_type":"spdisplays_internal","_spdisplays_resolution":"1800 x 1169 @ 120.00Hz","spdisplays_pixelresolution":"spdisplays_3024x1964Retina"},
  {"_name":"ARZOPA","_spdisplays_display-serial-number":"74646035","_spdisplays_resolution":"1920 x 1080 @ 144.00Hz"}
]}]}
EOF
PROFILER_JSON="$tmp/arzopa-dock.json"
DISPLAYPLACER_LIST="$REAL"
out="$(run_macos --only @arzopa-display)"
has "the real dock list is ok at 144Hz" \
  "ok    ARZOPA is 1920x1080 at 144Hz, the highest this connection offers (180Hz needs a direct connection)" "$out"
miss "the real dock list does not set a mode" "CALL id:" "$(cat "$placerlog")"
has "the real dock list is not a warning" "0 warning(s)" "$out"

# The same list with the ARZOPA on 100Hz: macos.sh sets the 144Hz mode.
sed -e '151s/^Hertz: 144$/Hertz: 100/' \
  -e 's/^\(  mode 61: res:1920x1080 hz:144 color_depth:8\) <-- current mode$/\1/' \
  -e 's/^\(  mode 63: res:1920x1080 hz:100 color_depth:8\)$/\1 <-- current mode/' \
  "$REAL" > "$tmp/real-dock-100.txt"
cp "$REAL" "$tmp/real-dock-100.txt.144"
DISPLAYPLACER_LIST="$tmp/real-dock-100.txt"
out="$(run_macos --only @arzopa-display)"
has "the real dock list at 100Hz is set to 144Hz" \
  "set ARZOPA 1920x1080 at 144Hz, scaling off, left of the laptop" "$out"
has "that set uses the real ARZOPA id, unscaled" \
  "id:82BDB23E-5EA1-4C6F-925B-EB392903EC5E res:1920x1080 hz:144 color_depth:8 enabled:true scaling:off origin:(-1920,0) degree:0" \
  "$(cat "$placerlog")"
has "that set keeps the laptop on its marked mode" \
  "id:37D8832A-2D66-02CA-B9F7-8F30A301B230 mode:66 origin:(0,0) degree:0" "$(cat "$placerlog")"
miss "that set is not a warning" "could not set" "$out"
PROFILER_JSON="$tmp/arzopa.json"

# Dry run: the plan is shown and no rate is tried.
DISPLAYPLACER_LIST="$tmp/dock-100.txt"
out="$(run_macos --dry-run --only @arzopa-display)"
has "dry-run would set the dock to 144Hz" "would set ARZOPA 1920x1080 at 144Hz" "$out"
miss "dry-run does not set the dock" "CALL id:" "$(cat "$placerlog")"

printf 'live-apply tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
