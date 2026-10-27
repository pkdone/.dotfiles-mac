# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# scripts/manual-steps.sh calls the check_step_* functions (@macconfig:display).
# ---- 6b. Display auto-brightness ----------------------------------------
# Read-only. corebrightnessdiag status-info needs no sudo. The saved value is
# the root-owned CoreBrightness plist, and published writers also change True
# Tone, so this is not applied here or by --fix.
check_step_auto_brightness() {
  fixid auto-brightness
  CHECKED=$((CHECKED + 1))
  # Same override bootstrap.sh uses. Unset, this is still the system tool.
  ab_diag="${AUTO_BRIGHTNESS_DIAG:-/usr/libexec/corebrightnessdiag}"
  if [ ! -x "$ab_diag" ]; then
    fixid tooling
    warn "corebrightnessdiag missing — can't check Automatically adjust brightness"
  elif [ ! -r "$DOTDIR/lib/auto-brightness.py" ]; then
    fixid repo-file
    warn "lib/auto-brightness.py missing — can't check Automatically adjust brightness"
  elif ! PY="$(dot_python)"; then
    fixid tooling
    warn "no python3 — can't check Automatically adjust brightness"
  else
    diag_out="$(with_timeout 15 "$ab_diag" status-info 2>/dev/null || true)"
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
}

# ---- 6c. Built-in display More Space and the ARZOPA pin -----------------
# system_profiler SPDisplaysDataType -json. lib/display-resolution.list maps
# the panel size to its More Space prefix (14" 1800 x 1169, 16" 2056 x 1329)
# and pins the ARZOPA portable monitor when it is connected.
# An unlisted panel size, no built-in panel (clamshell), or no ARZOPA does
# not apply. The check prints an info line and does not count it in the ok
# total or the by-hand count. displayplacer list is read-only, and only when that
# tool is installed and the ARZOPA is connected, so the position can be
# checked. This section does not change a display. macos.sh applies a
# mismatch when it can. Manual steps display-more-space and arzopa-display
# are the fallback.
#
# DISPLAY_RESOLUTION_REPORT caches one read for both checks. The section
# unsets it first. A later macconfig process reads the displays again.
gather_display_resolution() {
  if [ -n "${DISPLAY_RESOLUTION_REPORT+x}" ]; then
    printf '%s\n' "$DISPLAY_RESOLUTION_REPORT"
    return 0
  fi
  local json placer_file report
  DISP_HELPER="$DOTDIR/lib/display-resolution.py"
  DISP_LIST="$DOTDIR/lib/display-resolution.list"
  if ! command -v system_profiler >/dev/null 2>&1; then
    DISPLAY_RESOLUTION_REPORT="error||system_profiler not available — can't check the displays"
  elif [ ! -r "$DISP_HELPER" ] || [ ! -r "$DISP_LIST" ]; then
    DISPLAY_RESOLUTION_REPORT="error||display resolution check files missing — can't check the displays"
  elif [ -z "$DOT_PYTHON" ]; then
    DISPLAY_RESOLUTION_REPORT="error||no python3 — can't check the displays"
  else
    if json="$(with_timeout 30 system_profiler SPDisplaysDataType -json </dev/null 2>/dev/null)"; then
      :
    else
      json=""
    fi
    if [ -z "$json" ]; then
      DISPLAY_RESOLUTION_REPORT="error||system_profiler SPDisplaysDataType failed — can't check the displays"
    else
      report="$(printf '%s\n' "$json" | "$DOT_PYTHON" "$DISP_HELPER" --list "$DISP_LIST" || true)"
      if printf '%s\n' "$report" | grep -q '^pending|'; then
        if command -v displayplacer >/dev/null 2>&1; then
          placer_file="$(mktemp)"
          with_timeout 15 displayplacer list >"$placer_file" </dev/null 2>/dev/null || true
          report="$(printf '%s\n' "$json" | "$DOT_PYTHON" "$DISP_HELPER" --list "$DISP_LIST" --placer "$placer_file" || true)"
          rm -f "$placer_file"
        fi
        report="$(printf '%s\n' "$report" | sed 's/^pending|/warn|/')"
      fi
      DISPLAY_RESOLUTION_REPORT="$report"
    fi
  fi
  printf '%s\n' "$DISPLAY_RESOLUTION_REPORT"
}

# display_resolution_pick TOPIC — sets DISP_LINE. TOPIC "" is the built-in
# panel. TOPIC arzopa is the portable monitor. The gather runs in this shell
# so the cache is still there for the second check.
display_resolution_pick() {
  local topic="$1" row rest got
  gather_display_resolution >/dev/null
  DISP_LINE=""
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    rest="${row#*|}"
    got="${rest%%|*}"
    if [ "$got" = "$topic" ]; then
      DISP_LINE="$row"
      return 0
    fi
  done <<< "$DISPLAY_RESOLUTION_REPORT"
  return 1
}

check_step_display_more_space() {
  fixid display-more-space
  local disp_line disp_status disp_msg
  display_resolution_pick "" || true
  disp_line="$DISP_LINE"
  if [ -z "$disp_line" ]; then
    CHECKED=$((CHECKED + 1))
    fixid tooling
    warn "display resolution check failed"
    return 0
  fi
  disp_status="${disp_line%%|*}"
  disp_msg="${disp_line#*|}"; disp_msg="${disp_msg#*|}"
  case "$disp_status" in
    ok) CHECKED=$((CHECKED + 1)); pass "$disp_msg" ;;
    # Clamshell or an unlisted panel: does not apply. skip prints the info
    # line and manualsteps does not walk the step.
    info) skip "$disp_msg" ;;
    warn)
      CHECKED=$((CHECKED + 1))
      fixid display-more-space
      warn "$disp_msg"
      ;;
    *)
      CHECKED=$((CHECKED + 1))
      fixid tooling
      warn "${disp_msg:-display resolution check failed}"
      ;;
  esac
}

check_step_arzopa_display() {
  fixid arzopa-display
  local az_line az_status az_msg
  display_resolution_pick arzopa || true
  az_line="$DISP_LINE"
  if [ -z "$az_line" ]; then
    CHECKED=$((CHECKED + 1))
    fixid tooling
    warn "ARZOPA display was not checked because the display report could not be read"
    return 0
  fi
  az_status="${az_line%%|*}"
  az_msg="${az_line#*|}"; az_msg="${az_msg#*|}"
  case "$az_status" in
    ok) CHECKED=$((CHECKED + 1)); pass "$az_msg" ;;
    # Not connected: does not apply. skip prints the info line and
    # manualsteps does not walk the step.
    info) skip "$az_msg" ;;
    warn)
      CHECKED=$((CHECKED + 1))
      fixid arzopa-display
      warn "$az_msg"
      ;;
    *)
      CHECKED=$((CHECKED + 1))
      fixid tooling
      warn "${az_msg:-ARZOPA display check failed}"
      ;;
  esac
}

# ---- 6c2. Wallpaper (check-only) ----------------------------------------
# The desktop picture is Tahoe Night (Landscape). The asset id is read from
# the wallpaper store. A miss is a warning. There is no reliable command for
# this system picture (it is a wallpaper-catalog asset, not a file), so
# nothing here changes it and the wallpaper store is not written.
# Manual step wallpaper points here.
check_step_wallpaper() {
  fixid wallpaper
  CHECKED=$((CHECKED + 1))
  WALL_HELPER="$DOTDIR/lib/wallpaper-asset.py"
  WALL_STORE="$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
  if [ ! -r "$WALL_HELPER" ]; then
    fixid repo-file
    warn "lib/wallpaper-asset.py missing — can't check the desktop picture"
  elif [ -z "$DOT_PYTHON" ]; then
    fixid tooling
    warn "no python3 — can't check the desktop picture"
  else
    wall_line="$("$DOT_PYTHON" "$WALL_HELPER" --text "$WALL_STORE" || true)"
    wall_status="${wall_line%%|*}"
    wall_msg="${wall_line#*|}"; wall_msg="${wall_msg#*|}"
    case "$wall_status" in
      ok) pass "$wall_msg" ;;
      *)  fixid wallpaper; warn "${wall_msg:-desktop picture check failed}" ;;
    esac
  fi
}

# ---- 6c3. Account picture (the Dog, check-only) -------------------------
# SHA-256 of the JPEGPhoto on the user account. The hash is
# lib/user-picture.sha256. A different picture is a warning. --fix does not
# change it. Manual step user-picture points here.
check_step_user_picture() {
  fixid user-picture
  pic_helper="$DOTDIR/lib/user-picture.py"
  pic_hash="$DOTDIR/lib/user-picture.sha256"
  if [ ! -r "$pic_helper" ] || [ ! -r "$pic_hash" ]; then
    CHECKED=$((CHECKED + 1))
    fixid repo-file
    warn "user picture files missing — can't check the account picture"
  elif [ -z "$DOT_PYTHON" ]; then
    CHECKED=$((CHECKED + 1))
    fixid tooling
    warn "no python3 — can't check the account picture"
  elif ! command -v dscl >/dev/null 2>&1; then
    info "dscl not found — the account picture stays by hand"
  else
    CHECKED=$((CHECKED + 1))
    pic_dump="$(with_timeout 15 dscl . -read "/Users/$USER" JPEGPhoto 2>/dev/null || true)"
    pic_line="$(printf '%s\n' "$pic_dump" | "$DOT_PYTHON" "$pic_helper" --expect "$pic_hash" || true)"
    pic_status="${pic_line%%|*}"
    pic_msg="${pic_line#*|}"; pic_msg="${pic_msg#*|}"
    case "$pic_status" in
      ok) pass "$pic_msg" ;;
      *) fixid user-picture; warn "${pic_msg:-account picture check failed}" ;;
    esac
  fi
}

if [ "${MACCONFIG_CHECKS_DEFINE_ONLY:-}" = 1 ]; then
  return 0
fi

hdr "Display auto-brightness"
check_step_auto_brightness
hdr "Display (More Space)"
unset DISPLAY_RESOLUTION_REPORT
check_step_display_more_space
hdr "ARZOPA display"
check_step_arzopa_display
hdr "Wallpaper"
check_step_wallpaper

# ---- 6c25. Desktop widgets (removed, check-only) ------------------------
# StandardHideWidgets hides widgets. It does not delete them. Placed widgets
# are widgets → instances in the notificationcenterui plist, one data blob
# each, and they still show when the desktop is revealed.
# lib/desktop-widgets.py only reads that plist. This section does not write
# it and does not kill NotificationCenter or chronod. macconfig --fix does
# not either (remove-widgets in lib/autofix.list is report-only). Manual step
# remove-widgets is the removal. WIDGETS_SECTION_RAN tells checks/manual.sh
# not to print the same result again; `manualsteps open` still uses the check,
# so the step is shown only when a widget is placed.
hdr "Desktop widgets"
WIDGETS_SECTION_RAN=1
fixid remove-widgets
WIDGETS_HELPER="$DOTDIR/lib/desktop-widgets.py"
if [ ! -r "$WIDGETS_HELPER" ]; then
  CHECKED=$((CHECKED + 1))
  fixid repo-file
  warn "lib/desktop-widgets.py missing — can't check desktop widgets"
elif [ -z "$DOT_PYTHON" ]; then
  CHECKED=$((CHECKED + 1))
  fixid tooling
  warn "no python3 — can't check desktop widgets"
else
  widgets_line="$(with_timeout 15 "$DOT_PYTHON" "$WIDGETS_HELPER" </dev/null 2>/dev/null || true)"
  widgets_status="${widgets_line%%|*}"
  widgets_msg="${widgets_line#*|}"
  widgets_msg="${widgets_msg#*|}"
  # The fallback stays outside ${var:-...}: an apostrophe there breaks bash.
  widgets_hand="can't read the desktop widget list — check by hand"
  case "$widgets_status" in
    ok)
      CHECKED=$((CHECKED + 1))
      pass "$widgets_msg"
      ;;
    warn)
      CHECKED=$((CHECKED + 1))
      fixid remove-widgets
      warn "$widgets_msg"
      ;;
    hand)
      info "${widgets_msg:-$widgets_hand}"
      ;;
    *)
      info "$widgets_hand"
      ;;
  esac
fi

hdr "User picture"
check_step_user_picture
