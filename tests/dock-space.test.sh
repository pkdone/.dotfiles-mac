#!/usr/bin/env bash
# SC2317: the section's helpers are stubs called by the sourced checks/dock.sh.
# SC2034: DOTDIR is read by the sourced checks/dock.sh.
# shellcheck disable=SC2317,SC2034
#
# Space kept for the Dock. With auto-hide off, macOS takes the Dock out of the
# usable screen area so Fill stops at it. When it stops doing that, the Dock
# section warns (tagged dock-space), and --fix restarts the Dock and measures
# again. defaults, hs, pgrep, osascript, killall, sleep and dockutil are stubs
# on a closed PATH (tests/hermetic.sh), so nothing on this machine is read and
# no real Dock is restarted.
# Run: ./tests/dock-space.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hermetic.sh disable=SC1091
. "$DIR/tests/hermetic.sh"

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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
SAFE="$(hermetic_safe_root)"
bin="$tmp/bin"
state="$tmp/state"
mkdir -p "$bin" "$state" "$tmp/home"

# Paul's MacBook: 1800x1169, menu bar 39 points. Broken: only the menu bar is
# taken out. After killall Dock: 48 points kept at the bottom.
BROKEN='0 0 1800 1169 0 39 1800 1130'
FIXED='0 0 1800 1169 0 39 1800 1082'

# Stubs. DOCK_AUTOHIDE / DOCK_ORIENT unset = the key is missing (exit 1).
# hs and osascript print HS_OUT / JXA_OUT, or AFTER_OUT once killall ran.
cat > "$bin/defaults" <<'EOF'
#!/bin/sh
[ "$1 $2" = "read com.apple.dock" ] || exit 1
case "$3" in
  autohide) [ -n "${DOCK_AUTOHIDE+x}" ] || exit 1; printf '%s\n' "$DOCK_AUTOHIDE" ;;
  orientation) [ -n "${DOCK_ORIENT+x}" ] || exit 1; printf '%s\n' "$DOCK_ORIENT" ;;
  *) exit 1 ;;
esac
EOF
cat > "$bin/pgrep" <<'EOF'
#!/bin/sh
[ "$*" = "-xq Hammerspoon" ] && [ "${HS_RUNNING:-0}" = 1 ]
EOF
cat > "$bin/hs" <<'EOF'
#!/bin/sh
printf 'hs %s\n' "$1" >> "$STATE/calls"
if [ -f "$STATE/restarted" ] && [ -n "${AFTER_OUT+x}" ]; then printf '%s\n' "$AFTER_OUT"; else printf '%s\n' "${HS_OUT:-}"; fi
exit "${HS_RC:-0}"
EOF
cat > "$bin/osascript" <<'EOF'
#!/bin/sh
printf 'osascript %s %s\n' "$1" "$2" >> "$STATE/calls"
if [ -f "$STATE/restarted" ] && [ -n "${AFTER_OUT+x}" ]; then printf '%s\n' "$AFTER_OUT"; else printf '%s\n' "${JXA_OUT:-}"; fi
EOF
cat > "$bin/killall" <<'EOF'
#!/bin/sh
printf 'killall %s\n' "$*" >> "$STATE/calls"
[ "${KILLALL_RC:-0}" = 0 ] || exit "$KILLALL_RC"
: > "$STATE/restarted"
EOF
cat > "$bin/sleep" <<'EOF'
#!/bin/sh
printf 'sleep %s\n' "$*" >> "$STATE/calls"
EOF
cat > "$bin/dockutil" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$bin"/*

# reset — forget the previous case's stub settings and calls.
reset() {
  rm -f "$state/calls" "$state/restarted"
  : > "$state/calls"
  unset DOCK_AUTOHIDE DOCK_ORIENT HS_OUT HS_RC JXA_OUT AFTER_OUT KILLALL_RC
  HS_RUNNING=0
}
export STATE="$state" HS_RUNNING=0
calls() { cat "$state/calls"; }

with_timeout() { shift; "$@"; }
export MACCONFIG_CHECKS_DEFINE_ONLY=1
# shellcheck source=../checks/dock.sh disable=SC1091
. "$DIR/checks/dock.sh"
unset MACCONFIG_CHECKS_DEFINE_ONLY

# ---- dock_space_verdict ------------------------------------------------------
v() { printf '%s\n' "$2" | dock_space_verdict "$1"; }
eq "Paul's broken screen: nothing kept at the bottom" \
  "missing|0,39 1800x1130|1800x1169" "$(v bottom "$BROKEN")"
eq "after the restart 48 points are kept" "ok|48" "$(v bottom "$FIXED")"
eq "left Dock keeps its width on the left" "ok|48" "$(v left '0 0 1800 1169 48 39 1752 1130')"
eq "a left Dock is not measured at the bottom" "missing|48,39 1752x1130|1800x1169" \
  "$(v bottom '0 0 1800 1169 48 39 1752 1130')"
eq "right Dock keeps its width on the right" "ok|48" "$(v right '0 0 1800 1169 0 39 1752 1130')"
eq "a right Dock with nothing kept is missing" "missing|0,39 1800x1130|1800x1169" "$(v right "$BROKEN")"
two="$(printf '%s\n%s' '-1920 0 1920 1080 -1920 0 1920 1080' "$FIXED")"
eq "the ARZOPA has no Dock, the laptop does: ok" "ok|48" "$(v bottom "$two")"
eq "the Dock moved to the ARZOPA: ok" "ok|48" \
  "$(v bottom "$(printf '%s\n%s' '-1920 0 1920 1080 -1920 0 1920 1032' "$BROKEN")")"
eq "neither display keeps space: the laptop, which shows the menu bar, is named" \
  "missing|0,39 1800x1130|1800x1169" \
  "$(v bottom "$(printf '%s\n%s' '-1920 0 1920 1080 -1920 0 1920 1080' "$BROKEN")")"
eq "a full-screen app hides the menu bar too: can't tell" "menubar" "$(v bottom '0 0 1800 1169 0 0 1800 1169')"
eq "a few points of rounding are not a Dock" "missing|0,39 1800x1128|1800x1169" \
  "$(v bottom '0 0 1800 1169 0 39 1800 1128')"
eq "no frame lines prints nothing" "" "$(v bottom '')"
eq "frame lines: garbage is dropped" "$BROKEN" \
  "$(printf '%s\n' '-- Loading extension: screen' 'error: nope' "$BROKEN" '1 2 3' 'a b c d e f g h' | dock_frame_lines)"

# ---- orientation and auto-hide ------------------------------------------------
orient() { PATH="$bin:$SAFE" dock_orientation; }
autohide() { if PATH="$bin:$SAFE" dock_autohide_on; then echo on; else echo off; fi; }
reset
eq "orientation unset is bottom" bottom "$(orient)"
eq "orientation left" left "$(DOCK_ORIENT=left orient)"
eq "orientation right" right "$(DOCK_ORIENT=right orient)"
eq "an unknown orientation is bottom" bottom "$(DOCK_ORIENT=top orient)"
eq "autohide unset is off" off "$(autohide)"
eq "autohide 0 is off" off "$(DOCK_AUTOHIDE=0 autohide)"
eq "autohide 1 is on" on "$(DOCK_AUTOHIDE=1 autohide)"
eq "no defaults command: bottom" bottom "$(PATH="$SAFE" dock_orientation)"
eq "no defaults command: autohide off" off "$(if PATH="$SAFE" dock_autohide_on; then echo on; else echo off; fi)"

# ---- dock_screen_frames ---------------------------------------------------
frames() { PATH="$bin:$SAFE" dock_screen_frames; }
reset
HS_RUNNING=1; HS_OUT="$FIXED"; JXA_OUT="$BROKEN"; export HS_RUNNING HS_OUT JXA_OUT
eq "Hammerspoon running: hs answers" "$FIXED" "$(frames)"
has "hs got the Lua code" "hs -c" "$(calls)"
miss "osascript is not needed" "osascript" "$(calls)"

reset
JXA_OUT="$BROKEN"; HS_OUT="$FIXED"; export JXA_OUT HS_OUT
eq "Hammerspoon not running: NSScreen through osascript" "$BROKEN" "$(frames)"
miss "hs is not asked when Hammerspoon is not running" "hs -c" "$(calls)"
has "osascript runs JavaScript" "osascript -l JavaScript" "$(calls)"

reset
HS_RUNNING=1; HS_OUT="error: can't access Hammerspoon message port"; HS_RC=69; JXA_OUT="$BROKEN"
export HS_RUNNING HS_OUT HS_RC JXA_OUT
eq "hs fails: falls back to osascript" "$BROKEN" "$(frames)"

reset
eq "no hs, no osascript: nothing" "" "$(PATH="$SAFE" dock_screen_frames)"
eq "osascript prints nothing useful: nothing" "" "$(JXA_OUT=Tailscale frames)"

# ---- the Dock section, under macconfig-check.sh's shell options -----------
dotdir="$tmp/dotdir"
mkdir -p "$dotdir/lib"
: > "$dotdir/lib/dock-apps.list"
run_dock_section() (
  set -euo pipefail
  PATH="$bin:$SAFE"
  DOTDIR="$dotdir"
  HOME="$tmp/home"
  CHECKED=0
  hdr() { printf '[%s]\n' "$1"; }
  fixid() { printf 'fixid %s\n' "$1"; }
  pass() { printf 'ok %s\n' "$1"; }
  bad() { printf 'DRIFT %s\n' "$1"; }
  warn() { printf 'warn %s\n' "$1"; }
  skip() { printf 'skip %s\n' "$1"; }
  with_timeout() { shift; "$@"; }
  # shellcheck source=../checks/dock.sh disable=SC1091
  . "$DIR/checks/dock.sh"
  printf 'checked %s\n' "$CHECKED"
)

reset
HS_RUNNING=1; HS_OUT="$BROKEN"; export HS_RUNNING HS_OUT
out="$(run_dock_section)"
has "Paul's broken screen warns in plain English" \
  "warn The Dock is showing but macOS isn't keeping space for it, so Fill puts windows under it (usable area 0,39 1800x1130 of 1800x1169, nothing kept at the bottom)" "$out"
has "the warning is tagged dock-space" "fixid dock-space" "$out"
miss "it is not drift" "DRIFT" "$out"
has "the Dock apps and the space are both counted" "checked 2" "$out"
miss "the check does not restart the Dock" "killall" "$(calls)"

reset
HS_RUNNING=1; HS_OUT="$FIXED"; export HS_RUNNING HS_OUT
out="$(run_dock_section)"
has "space kept passes" "ok macOS keeps 48 points for the Dock at the bottom of the screen" "$out"
has "a pass is counted" "checked 2" "$out"

reset
DOCK_ORIENT=left; JXA_OUT='0 0 1800 1169 48 39 1752 1130'; export DOCK_ORIENT JXA_OUT
out="$(run_dock_section)"
has "a left Dock is measured on the left, through osascript" \
  "ok macOS keeps 48 points for the Dock on the left of the screen" "$out"

reset
DOCK_ORIENT=right; JXA_OUT="$BROKEN"; export DOCK_ORIENT JXA_OUT
out="$(run_dock_section)"
has "a right Dock with nothing kept warns about the right" "nothing kept on the right" "$out"

reset
DOCK_AUTOHIDE=1; HS_RUNNING=1; HS_OUT="$BROKEN"; export DOCK_AUTOHIDE HS_RUNNING HS_OUT
out="$(run_dock_section)"
has "auto-hide on is not checked" "skip the Dock hides itself" "$out"
miss "auto-hide on does not warn" "warn" "$out"
has "auto-hide on is not counted" "checked 1" "$out"
eq "auto-hide on measures nothing" "" "$(calls)"

reset
out="$(run_dock_section)"
has "nothing to measure with: the section still finishes" "checked 1" "$out"
miss "nothing to measure with: no line about the space" "keep" "$out"
miss "nothing to measure with: no warning" "warn" "$out"

reset
HS_RUNNING=1; HS_OUT="garbage"; HS_RC=1; export HS_RUNNING HS_OUT HS_RC
out="$(run_dock_section)"
has "hs fails and there is no osascript answer: the section still finishes" "checked 1" "$out"

reset
JXA_OUT='0 0 1800 1169 0 0 1800 1169'; export JXA_OUT
out="$(run_dock_section)"
has "a full-screen app: can't be measured" "skip the menu bar is hidden too" "$out"
has "a full-screen app is not counted" "checked 1" "$out"

reset
mkdir -p "$tmp/bin-nodefaults"
for f in "$bin"/*; do
  [ "$(basename "$f")" = defaults ] || ln -s "$f" "$tmp/bin-nodefaults/$(basename "$f")"
done
JXA_OUT="$BROKEN"; export JXA_OUT
out="$(bin="$tmp/bin-nodefaults" run_dock_section)"
has "no defaults command: still checked as a bottom Dock" "nothing kept at the bottom" "$out"

# ---- dock_space_restart (the --fix) ----------------------------------------
restart() { PATH="$bin:$SAFE" DOCK_SPACE_WAIT=3 dock_space_restart; }
reset
HS_RUNNING=1; HS_OUT="$BROKEN"; AFTER_OUT="$FIXED"; export HS_RUNNING HS_OUT AFTER_OUT
rc=0; out="$(DRY_RUN=1 restart)" || rc=$?
eq "dry run succeeds" 0 "$rc"
eq "dry run says what it would do" "would restart the Dock (killall Dock) and measure the screen again" "$out"
miss "dry run does not restart the Dock" "killall" "$(calls)"

reset
HS_RUNNING=1; HS_OUT="$BROKEN"; AFTER_OUT="$FIXED"; export HS_RUNNING HS_OUT AFTER_OUT
rc=0; out="$(restart)" || rc=$?
eq "restart that brings the space back succeeds" 0 "$rc"
eq "it reports what macOS keeps now" "restarted the Dock; macOS keeps 48 points for it at the bottom again" "$out"
has "it restarted the Dock" "killall Dock" "$(calls)"
eq "it stops waiting once the space is back" 1 "$(grep -c '^sleep' "$state/calls")"

reset
HS_RUNNING=1; HS_OUT="$BROKEN"; AFTER_OUT="$BROKEN"; export HS_RUNNING HS_OUT AFTER_OUT
rc=0; out="$(restart)" || rc=$?
eq "a restart that does not help fails" 1 "$rc"
eq "it says the space is still missing" \
  "restarted the Dock, but macOS still isn't keeping space for it (usable area 0,39 1800x1130 of 1800x1169)" "$out"
eq "it waits DOCK_SPACE_WAIT seconds" 3 "$(grep -c '^sleep 1$' "$state/calls")"

reset
HS_RUNNING=1; HS_OUT="$BROKEN"; AFTER_OUT=""; export HS_RUNNING HS_OUT AFTER_OUT
rc=0; out="$(restart)" || rc=$?
eq "a restart that can't be measured afterwards fails" 1 "$rc"
has "it says so" "could not be measured afterwards" "$out"

reset
KILLALL_RC=1; export KILLALL_RC
rc=0; out="$(restart)" || rc=$?
eq "killall failing fails" 1 "$rc"
eq "killall failing says so" "killall Dock failed" "$out"
eq "killall failing does not wait" 0 "$(grep -c '^sleep' "$state/calls")"

# ---- macconfig-check.sh --only dock --fix, end to end ----------------------
# The real lib/dock-apps.list is used and dockutil lists nothing, so the Dock
# apps drift too (Needs Paul). Only the dock-space lines are checked here.
e2e() {
  local rc=0
  out="$(HOME="$tmp/home" PATH="$bin:$SAFE" NO_COLOR=1 "$DIR/macconfig-check.sh" --no-color --only dock "$@" 2>&1)" || rc=$?
  printf '%s\n%s\n' "$rc" "$out"
}
reset
HS_RUNNING=1; HS_OUT="$BROKEN"; AFTER_OUT="$FIXED"; export HS_RUNNING HS_OUT AFTER_OUT
plain="$(e2e)"
has "the plain run warns" "warn  The Dock is showing but macOS isn't keeping space for it" "$plain"
has "the summary says --fix can repair it" "fix: dock-space" "$plain"
miss "the plain run restarts nothing" "killall" "$(calls)"

reset
HS_RUNNING=1; HS_OUT="$BROKEN"; AFTER_OUT="$FIXED"; export HS_RUNNING HS_OUT AFTER_OUT
dry="$(e2e --fix --dry-run)"
has "dry run lists the restart" "would restart the Dock (killall Dock)" "$dry"
miss "dry run restarts nothing" "killall" "$(calls)"

reset
HS_RUNNING=1; HS_OUT="$BROKEN"; AFTER_OUT="$FIXED"; export HS_RUNNING HS_OUT AFTER_OUT
fixed="$(e2e --fix)"
has "--fix restarts the Dock once" "killall Dock" "$(calls)"
eq "--fix restarts the Dock only once" 1 "$(grep -c '^killall' "$state/calls")"
has "--fix reports the space is back" "Fixed (1):" "$fixed"
has "--fix names what macOS keeps now" \
  "Restarting the Dock fixes it → restarted the Dock; macOS keeps 48 points for it at the bottom again" "$fixed"
miss "the re-check no longer warns about it" "(fix: dock-space)" "$fixed"
miss "it is not left for Paul" "fix didn't stick" "$fixed"
has "--fix logs the restart" "fixed: The Dock is showing" "$(cat "$tmp/home/Library/Logs/com.pdone.check-fix.log")"

reset
HS_RUNNING=1; HS_OUT="$BROKEN"; AFTER_OUT="$BROKEN"; export HS_RUNNING HS_OUT AFTER_OUT
still="$(e2e --fix)"
has "a restart that does not help is left for Paul" \
  "Restarting the Dock fixes it — fix didn't stick (still: The Dock is showing" "$still"
has "and says the space is still missing" "restarted the Dock, but macOS still isn't keeping space for it" "$still"
has "the warning stays in the summary" "(fix: dock-space)" "$still"

printf 'dock-space tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
