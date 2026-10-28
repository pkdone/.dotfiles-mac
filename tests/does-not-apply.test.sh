#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2030,SC2031,SC2317
#
# A check that does not apply prints an info line and is left out of the ok
# total and the by-hand count. With the ARZOPA unplugged, the summary's two
# ok numbers match. A connected monitor, a warning, and a check you still do
# by hand keep their own counts. Nothing here talks to a real display.
# Run: ./tests/does-not-apply.test.sh
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
mkdir -p "$tmp/bin" "$tmp/home"
SAFE="$(hermetic_safe_root)"
PY="$(PATH="$SAFE" command -v python3 || true)"
if [ -z "$PY" ]; then echo "does-not-apply tests: python3 not found, skipped"; exit 0; fi

# The same pass/warn/info/note/skip macconfig-check.sh uses, so a skip that
# went back to counting by hand fails here.
COUNTERS="$(awk '
  /^pass\(\) \{/ {p=1}
  /^with_timeout\(\) \{/ {p=0}
  p
' "$DIR/macconfig-check.sh")"

cat > "$tmp/bin/system_profiler" <<'EOF'
#!/bin/sh
cat "$PROFILER_JSON"
EOF
cat > "$tmp/bin/displayplacer" <<'EOF'
#!/bin/sh
cat "$PLACER_FILE"
EOF
chmod +x "$tmp/bin/system_profiler" "$tmp/bin/displayplacer"
mkdir -p "$tmp/nop"
ln -s "$tmp/bin/system_profiler" "$tmp/nop/system_profiler"

cat > "$tmp/absent.json" <<'EOF'
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
cat > "$tmp/connected.json" <<'EOF'
{"SPDisplaysDataType":[{"spdisplays_ndrvs":[
  {"_name":"Color LCD","spdisplays_connection_type":"spdisplays_internal","_spdisplays_resolution":"1800 x 1169 @ 120.00Hz","spdisplays_pixelresolution":"spdisplays_3024x1964Retina"},
  {"_name":"ARZOPA","_spdisplays_display-serial-number":"s74646035","_spdisplays_resolution":"1920 x 1080 @ 180.00Hz"}
]}]}
EOF
cat > "$tmp/placer-ok.txt" <<'EOF'
Persistent screen id: NOT-THE-OLD-UUID
Serial screen id: s74646035
Screen name: ARZOPA
Type: 16 inch external screen
Resolution: 1920x1080
Hertz: 180
Color Depth: 8
Scaling: off
Origin: (-1920,0)
Rotation: 0
Resolutions for rotation 0:
  mode 11: res:1920x1080 hz:180 color_depth:8 <-- current mode

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
EOF

# $1 profiler json (empty: system_profiler is not on PATH)
# $2 displayplacer list (empty: displayplacer is not on PATH)
run_display() {
  (
    set -eu
    CHECKED=0; OKS=0; DRIFT=0; WARN=0; HAND=0
    C_OK=; C_BAD=; C_WARN=; C_HDR=; C_DIM=; C_OFF=
    US=$'\037'
    FIX_ID=unclassified; FIX_ARG=
    DRIFT_MSGS=(); WARN_MSGS=(); FIX_ITEMS=(); ATTN_ITEMS=()
    record() { :; }
    attn_push() { :; }
    fixid() { FIX_ID="$1"; FIX_ARG="${2:-}"; }
    hdr() { :; }
    with_timeout() { shift; "$@"; }
    # shellcheck disable=SC1090
    eval "$COUNTERS"
    unset DISPLAY_RESOLUTION_REPORT
    export DOTDIR="$DIR" DOT_PYTHON="$PY" HOME="$tmp/home"
    export PROFILER_JSON="${1:-}" PLACER_FILE="${2:-}"
    if [ -n "$1" ]; then
      export PATH="$tmp/bin:$SAFE"
    else
      export PATH="$SAFE"
    fi
    if [ -z "${2:-}" ] && [ -n "$1" ]; then
      # Profiler stub only. displayplacer stays off PATH, so a connected
      # monitor is reported and not positioned.
      export PATH="$tmp/nop:$SAFE"
    fi
    MACCONFIG_CHECKS_DEFINE_ONLY=1
    # shellcheck disable=SC1091
    . "$DIR/checks/display.sh"
    check_step_display_more_space
    check_step_arzopa_display
    printf 'COUNTS checked=%s ok=%s drift=%s warn=%s hand=%s\n' \
      "$CHECKED" "$OKS" "$DRIFT" "$WARN" "$HAND"
  )
}

absent="$(run_display "$tmp/absent.json")"
eq "unplugged ARZOPA: ok matches the total" \
  "COUNTS checked=1 ok=1 drift=0 warn=0 hand=0" \
  "$(printf '%s\n' "$absent" | grep '^COUNTS ')"
has "unplugged ARZOPA still prints the info line" \
  "  info  ARZOPA not connected — resolution and position not checked" "$absent"
miss "unplugged ARZOPA is not a warning" "  warn  " "$absent"

clam="$(run_display "$tmp/clamshell.json")"
eq "clamshell: nothing is counted" \
  "COUNTS checked=0 ok=0 drift=0 warn=0 hand=0" \
  "$(printf '%s\n' "$clam" | grep '^COUNTS ')"
has "clamshell still prints the More Space info line" \
  "  info  no built-in display — More Space not checked" "$clam"
has "clamshell still prints the ARZOPA info line" \
  "  info  ARZOPA not connected — resolution and position not checked" "$clam"

warned="$(run_display "$tmp/connected.json")"
eq "connected ARZOPA without displayplacer is a counted warning" \
  "COUNTS checked=2 ok=1 drift=0 warn=1 hand=0" \
  "$(printf '%s\n' "$warned" | grep '^COUNTS ')"
has "that warning names the ARZOPA" "  warn  " "$warned"
miss "a connected ARZOPA is not the unplugged line" "not connected" "$warned"

pinned="$(run_display "$tmp/connected.json" "$tmp/placer-ok.txt")"
eq "a connected ARZOPA that matches is counted ok" \
  "COUNTS checked=2 ok=2 drift=0 warn=0 hand=0" \
  "$(printf '%s\n' "$pinned" | grep '^COUNTS ')"
has "the matching ARZOPA line is ok" "  ok    ARZOPA is 1920x1080" "$pinned"

# Real displayplacer list with the ARZOPA on the StarTech dock at 144Hz.
cat > "$tmp/dock.json" <<'EOF'
{"SPDisplaysDataType":[{"spdisplays_ndrvs":[
  {"_name":"Color LCD","spdisplays_connection_type":"spdisplays_internal","_spdisplays_resolution":"1800 x 1169 @ 120.00Hz","spdisplays_pixelresolution":"spdisplays_3024x1964Retina"},
  {"_name":"ARZOPA","_spdisplays_display-serial-number":"74646035","_spdisplays_resolution":"1920 x 1080 @ 144.00Hz"}
]}]}
EOF
dock="$(run_display "$tmp/dock.json" "$DIR/tests/fixtures/displayplacer-dock.txt")"
eq "the real dock list is counted ok" \
  "COUNTS checked=2 ok=2 drift=0 warn=0 hand=0" \
  "$(printf '%s\n' "$dock" | grep '^COUNTS ')"
has "the real dock list passes at 144Hz" \
  "  ok    ARZOPA is 1920x1080 at 144Hz, the highest this connection offers (180Hz needs a direct connection)" "$dock"
miss "the real dock list does not say the mode is missing" "has no mode" "$dock"

missing="$(run_display "")"
eq "an unreadable display report is a counted warning" \
  "COUNTS checked=2 ok=0 drift=0 warn=2 hand=0" \
  "$(printf '%s\n' "$missing" | grep '^COUNTS ')"

# manualsteps still sees skip as "does not apply", so the walk-through
# does not open the step.
az_step="$(
  set -eu
  with_timeout() { shift; "$@"; }
  export DOTDIR="$DIR" DOT_PYTHON="$PY" HOME="$tmp/home" NO_COLOR=1
  export PROFILER_JSON="$tmp/absent.json" PATH="$tmp/bin:$SAFE"
  unset DISPLAY_RESOLUTION_REPORT
  # shellcheck disable=SC1091
  . "$DIR/lib/covered-steps.sh"
  covered_step_run arzopa-display display
)"
eq "manualsteps leaves an unplugged ARZOPA unopened" "ok|" "$az_step"

# A desktop pin for an app that is not installed does not apply. An ok pin
# next to it is still counted. The stub stands in for desktop-bindings.py.
cat > "$tmp/bin/desktop-py" <<'EOF'
#!/bin/sh
printf '%s\n' 'ok|com.example.Keep|Keep is on Desktop 1'
printf '%s\n' 'skip||WhatsApp Web is not set up yet (manual step whatsapp-web)'
EOF
chmod +x "$tmp/bin/desktop-py"
desk="$(
  set -eu
  CHECKED=0; OKS=0; DRIFT=0; WARN=0; HAND=0
  C_OK=; C_BAD=; C_WARN=; C_HDR=; C_DIM=; C_OFF=
  US=$'\037'
  FIX_ID=unclassified; FIX_ARG=
  DRIFT_MSGS=(); WARN_MSGS=(); FIX_ITEMS=(); ATTN_ITEMS=()
  record() { :; }
  attn_push() { :; }
  fixid() { FIX_ID="$1"; FIX_ARG="${2:-}"; }
  hdr() { :; }
  dot_python() { printf '%s\n' "$tmp/bin/desktop-py"; }
  # shellcheck disable=SC1090
  eval "$COUNTERS"
  export DOTDIR="$DIR" PATH="$SAFE"
  # shellcheck disable=SC1091
  . "$DIR/checks/desktops.sh"
  printf 'COUNTS checked=%s ok=%s drift=%s warn=%s hand=%s\n' \
    "$CHECKED" "$OKS" "$DRIFT" "$WARN" "$HAND"
)"
eq "a missing app's desktop pin is not counted" \
  "COUNTS checked=1 ok=1 drift=0 warn=0 hand=0" \
  "$(printf '%s\n' "$desk" | grep '^COUNTS ')"
has "the missing app still prints" \
  "  info  WhatsApp Web is not set up yet (manual step whatsapp-web)" "$desk"

# Focus modes that cannot be read are a note: printed, and in neither count.
# A database that names the modes is still a counted ok.
focus_note="$(
  set -eu
  CHECKED=0; OKS=0; DRIFT=0; WARN=0; HAND=0
  C_OK=; C_BAD=; C_WARN=; C_HDR=; C_DIM=; C_OFF=
  US=$'\037'
  FIX_ID=unclassified; FIX_ARG=
  DRIFT_MSGS=(); WARN_MSGS=(); FIX_ITEMS=(); ATTN_ITEMS=()
  record() { :; }
  attn_push() { :; }
  fixid() { FIX_ID="$1"; FIX_ARG="${2:-}"; }
  hdr() { :; }
  # shellcheck disable=SC1090
  eval "$COUNTERS"
  export DOTDIR="$DIR" DOT_PYTHON="$PY" HOME="$tmp/home" PATH="$SAFE"
  MACCONFIG_CHECKS_DEFINE_ONLY=1
  # shellcheck disable=SC1091
  . "$DIR/checks/modes.sh"
  check_step_mode_focus_modes
  printf 'COUNTS checked=%s ok=%s drift=%s warn=%s hand=%s\n' \
    "$CHECKED" "$OKS" "$DRIFT" "$WARN" "$HAND"
)"
eq "unreadable Focus modes are not counted" \
  "COUNTS checked=0 ok=0 drift=0 warn=0 hand=0" \
  "$(printf '%s\n' "$focus_note" | grep '^COUNTS ')"
has "unreadable Focus modes still print" "  info  Focus modes not readable" "$focus_note"

mkdir -p "$tmp/focus-home/Library/DoNotDisturb/DB"
printf '%s\n' '{"a":{"name":"WebConf"},"b":{"name":"DeepWork"}}' \
  > "$tmp/focus-home/Library/DoNotDisturb/DB/ModeConfigurations.json"
focus_ok="$(
  set -eu
  CHECKED=0; OKS=0; DRIFT=0; WARN=0; HAND=0
  C_OK=; C_BAD=; C_WARN=; C_HDR=; C_DIM=; C_OFF=
  US=$'\037'
  FIX_ID=unclassified; FIX_ARG=
  DRIFT_MSGS=(); WARN_MSGS=(); FIX_ITEMS=(); ATTN_ITEMS=()
  record() { :; }
  attn_push() { :; }
  fixid() { FIX_ID="$1"; FIX_ARG="${2:-}"; }
  hdr() { :; }
  # shellcheck disable=SC1090
  eval "$COUNTERS"
  export DOTDIR="$DIR" DOT_PYTHON="$PY" HOME="$tmp/focus-home" PATH="$SAFE"
  MACCONFIG_CHECKS_DEFINE_ONLY=1
  # shellcheck disable=SC1091
  . "$DIR/checks/modes.sh"
  check_step_mode_focus_modes
  printf 'COUNTS checked=%s ok=%s drift=%s warn=%s hand=%s\n' \
    "$CHECKED" "$OKS" "$DRIFT" "$WARN" "$HAND"
)"
eq "Focus modes that exist are counted ok" \
  "COUNTS checked=1 ok=1 drift=0 warn=0 hand=0" \
  "$(printf '%s\n' "$focus_ok" | grep '^COUNTS ')"

printf 'does-not-apply tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
