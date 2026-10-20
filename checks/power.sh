# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 6d. AC idle sleep (check-only) -------------------------------------
# pmset -g custom needs no sudo. lib/ac-sleep.py reads only the 'AC Power:'
# sleep key, so displaysleep, the lock screen, and Battery Power are ignored.
# A value other than 0 is a warning, not drift: setting it is
# `sudo pmset -c sleep 0` (manual step ac-sleep). --fix does not run sudo.
# Closing the lid still sleeps the Mac.
hdr "AC idle sleep"
fixid ac-sleep
CHECKED=$((CHECKED + 1))
AC_HELPER="$DOTDIR/lib/ac-sleep.py"
if ! command -v pmset >/dev/null 2>&1; then
  fixid tooling
  warn "pmset missing — can't check AC idle sleep"
elif [ ! -r "$AC_HELPER" ]; then
  fixid repo-file
  warn "lib/ac-sleep.py missing — can't check AC idle sleep"
elif [ -z "$DOT_PYTHON" ]; then
  fixid tooling
  warn "no python3 — can't check AC idle sleep"
else
  ac_custom="$(with_timeout 15 pmset -g custom 2>/dev/null || true)"
  if [ -z "$ac_custom" ]; then
    fixid tooling
    warn "pmset -g custom returned nothing — can't check AC idle sleep"
  else
    ac_line="$(printf '%s\n' "$ac_custom" | "$DOT_PYTHON" "$AC_HELPER" || true)"
    ac_status="${ac_line%%|*}"
    ac_msg="${ac_line#*|}"; ac_msg="${ac_msg#*|}"
    case "$ac_status" in
      ok)  pass "$ac_msg" ;;
      bad) warn "$ac_msg" ;;
      *)   fixid tooling; warn "${ac_msg:-AC idle sleep check failed}" ;;
    esac
  fi
fi
