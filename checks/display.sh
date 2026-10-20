# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 6b. Display auto-brightness ----------------------------------------
# Read-only. corebrightnessdiag status-info needs no sudo. The saved value is
# the root-owned CoreBrightness plist, and published writers also change True
# Tone, so this is not applied here or by --fix.
hdr "Display auto-brightness"
fixid auto-brightness
CHECKED=$((CHECKED + 1))
if [ ! -x /usr/libexec/corebrightnessdiag ]; then
  fixid tooling
  warn "corebrightnessdiag missing — can't check Automatically adjust brightness"
elif [ ! -r "$DOTDIR/lib/auto-brightness.py" ]; then
  fixid repo-file
  warn "lib/auto-brightness.py missing — can't check Automatically adjust brightness"
elif ! PY="$(dot_python)"; then
  fixid tooling
  warn "no python3 — can't check Automatically adjust brightness"
else
  diag_out="$(with_timeout 15 /usr/libexec/corebrightnessdiag status-info 2>/dev/null || true)"
  if [ -z "$diag_out" ]; then
    fixid tooling
    warn "corebrightnessdiag status-info returned nothing — can't check Automatically adjust brightness"
  else
    ab_line="$(printf '%s\n' "$diag_out" | "$PY" "$DOTDIR/lib/auto-brightness.py" || true)"
    ab_status="${ab_line%%|*}"
    ab_msg="${ab_line#*|}"
    ab_msg="${ab_msg#*|}"
    case "$ab_status" in
      ok)  pass "$ab_msg" ;;
      bad) bad "$ab_msg" ;;
      *)   fixid tooling; warn "${ab_msg:-auto-brightness check failed}" ;;
    esac
  fi
fi

# ---- 6c. Built-in display More Space (check-only) -----------------------
# system_profiler SPDisplaysDataType -json. The expected prefix lives in
# lib/display-resolution.list (More Space on this Color LCD is 1800 x 1169).
# No built-in panel is an info skip (clamshell). --fix never changes the
# display mode. Manual step display-more-space points here.
hdr "Display (More Space)"
fixid display-more-space
CHECKED=$((CHECKED + 1))
DISP_HELPER="$DOTDIR/lib/display-resolution.py"
DISP_LIST="$DOTDIR/lib/display-resolution.list"
if ! command -v system_profiler >/dev/null 2>&1; then
  fixid tooling
  warn "system_profiler not available — can't check More Space"
elif [ ! -r "$DISP_HELPER" ] || [ ! -r "$DISP_LIST" ]; then
  fixid repo-file
  warn "display resolution check files missing — can't check More Space"
elif [ -z "$DOT_PYTHON" ]; then
  fixid tooling
  warn "no python3 — can't check More Space"
else
  if disp_json="$(with_timeout 30 system_profiler SPDisplaysDataType -json </dev/null 2>/dev/null)"; then
    disp_rc=0
  else
    disp_rc=$?
  fi
  if [ "$disp_rc" -ne 0 ] || [ -z "$disp_json" ]; then
    fixid tooling
    warn "system_profiler SPDisplaysDataType failed — can't check More Space"
  else
    disp_line="$(printf '%s\n' "$disp_json" | "$DOT_PYTHON" "$DISP_HELPER" --list "$DISP_LIST" || true)"
    disp_status="${disp_line%%|*}"
    disp_msg="${disp_line#*|}"; disp_msg="${disp_msg#*|}"
    case "$disp_status" in
      ok)   pass "$disp_msg" ;;
      info) info "$disp_msg" ;;
      warn)
        fixid display-more-space
        warn "$disp_msg"
        ;;
      *)
        fixid tooling
        warn "${disp_msg:-display resolution check failed}"
        ;;
    esac
  fi
fi
