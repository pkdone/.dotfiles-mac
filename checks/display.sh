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

# ---- 6c. Built-in display More Space ------------------------------------
# system_profiler SPDisplaysDataType -json. lib/display-resolution.list maps
# the panel size to its More Space prefix (14" 1800 x 1169, 16" 2056 x 1329).
# An unlisted panel size or no built-in panel (clamshell) is an info skip.
# This section only reads the display report. macos.sh applies a mismatch
# when it can. Manual step display-more-space is the fallback.
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

# ---- 6c2. Wallpaper (check-only) ----------------------------------------
# The desktop picture is Tahoe Night (Landscape). The asset id is read from
# the wallpaper store. A miss is a warning. There is no reliable command for
# this system picture (it is a wallpaper-catalog asset, not a file), so
# nothing here changes it and the wallpaper store is not written.
# Manual step wallpaper points here.
hdr "Wallpaper"
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

# ---- 6c3. Account picture (the Dog, check-only) -------------------------
# SHA-256 of the JPEGPhoto on the user account. The hash is
# lib/user-picture.sha256. A different picture is a warning. --fix does not
# change it. Manual step user-picture points here.
hdr "User picture"
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
