#!/usr/bin/env bash
#
# Live apply for dark mode, the trackpad, and built-in More Space.
# osascript, activateSettings, displayplacer, and system_profiler are stubs.
# Nothing here talks to a real display or System Events.
# Run: ./tests/live-apply.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
  /"\$MANUAL_STEPS" list/ { l = NR }
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
cat > "$bin/displayplacer" <<'EOF'
#!/usr/bin/env bash
printf 'CALL %s\n' "$*" >> "${DISPLAYPLACER_LOG:?}"
if [ "${1:-}" = "list" ]; then
  cat "${DISPLAYPLACER_LIST:?}"
  exit 0
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
  mode 0: res:1512x982 hz:120 color_depth:8 scaling:on
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
  mode 0: res:2560x1440 hz:60 color_depth:8 scaling:off
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
  mode 0: res:1512x982 hz:120 color_depth:8 scaling:on
EOF

BASE_PATH="${PATH:-/usr/bin:/bin}"
DARK='NSGlobalDomain|AppleInterfaceStyle'
TRACK='com.apple.AppleMultitouchTrackpad|TrackpadCornerSecondaryClick'
SPACES='com.apple.spaces|spans-displays'

run_macos() {
  : > "$dlog"
  : > "$olog"
  : > "$alog"
  : > "$plog"
  : > "$placerlog"
  : > "$logout"
  PATH="$bin:$BASE_PATH" \
    DEFAULTS_LOG="$dlog" DEFAULTS_STATE="$state" \
    OSASCRIPT_LOG="$olog" OSASCRIPT_GET="${OSASCRIPT_GET:-true}" OSASCRIPT_SET="${OSASCRIPT_SET:-ok}" \
    ACTIVATE_LOG="$alog" ACTIVATE_RC="${ACTIVATE_RC:-0}" \
    PROFILER_LOG="$plog" PROFILER_JSON="${PROFILER_JSON:-$tmp/not-more-space.json}" \
    DISPLAYPLACER_LOG="$placerlog" DISPLAYPLACER_LIST="${DISPLAYPLACER_LIST:-$tmp/placer.txt}" \
    DISPLAYPLACER_RC="${DISPLAYPLACER_RC:-0}" \
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
has "already More Space is skipped" "built-in display already More Space" "$out"
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

# Hide the stub. command -v must not find it.
mv "$bin/displayplacer" "$bin/displayplacer.off"
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

printf 'live-apply tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
