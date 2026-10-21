# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 6d. Sleep, display sleep, and wake (check-only) --------------------
# pmset -g custom needs no sudo. lib/ac-sleep.py reads AC sleep 0, AC display
# sleep 10, battery display sleep 2, and AC wake for network access (womp 1).
# Battery idle sleep is not read. A miss is a warning, not drift: setting it
# needs sudo (manual step ac-sleep). --fix does not run sudo.
# Closing the lid still sleeps the Mac.
hdr "Power (sleep and wake)"
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
