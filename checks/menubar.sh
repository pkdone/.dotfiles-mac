# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# scripts/manual-steps.sh calls check_step_menubar_third_party_hide
# (@macconfig:menubar).
# ---- Allow in the Menu Bar (check-only) ---------------------------------
# macOS 26 keeps the per-app toggles in trackedApplications, a nested binary
# plist inside the Control Center group preferences. lib/menubar-allow.py
# reads that blob and never writes it. Apps that must be off are
# lib/menubar-allow.list. One that is allowed is drift (Needs Paul). An app
# that is not installed, or not in the blob yet, is an info line (note: not
# counted). A missing or unreadable plist is a warning, not a failure.
# --fix does not touch this store. There is no SAFE writer.
menubar_prepare() {
  [ "${MENUBAR_PREPARED:-}" = 1 ] && return 0
  MENUBAR_PREPARED=1
  MENUBAR_HELPER="$DOTDIR/lib/menubar-allow.py"
  MENUBAR_OUT=""
  MENUBAR_RC=0
  MENUBAR_FAIL=""
  MENUBAR_FAIL_ID=menubar-allow
  if [ ! -r "$MENUBAR_HELPER" ]; then
    MENUBAR_FAIL="lib/menubar-allow.py missing — can't check Allow in the Menu Bar"
    MENUBAR_FAIL_ID=repo-file
  elif [ ! -r "$DOTDIR/lib/menubar-allow.list" ]; then
    MENUBAR_FAIL="lib/menubar-allow.list missing — can't check Allow in the Menu Bar"
    MENUBAR_FAIL_ID=repo-file
  elif [ -z "$DOT_PYTHON" ]; then
    MENUBAR_FAIL="no python3 — can't check Allow in the Menu Bar"
    MENUBAR_FAIL_ID=tooling
  else
    if MENUBAR_OUT="$(with_timeout 20 "$DOT_PYTHON" "$MENUBAR_HELPER" </dev/null 2>&1)"; then
      MENUBAR_RC=0
    else
      MENUBAR_RC=$?
    fi
  fi
}

menubar_fail_warn() {
  [ -n "${MENUBAR_FAIL:-}" ] || return 1
  if [ "${MENUBAR_FAIL_WARNED:-}" = 1 ]; then return 0; fi
  MENUBAR_FAIL_WARNED=1
  CHECKED=$((CHECKED + 1))
  fixid "$MENUBAR_FAIL_ID"
  warn "$MENUBAR_FAIL"
  return 0
}

check_step_menubar_third_party_hide() {
  local m_st m_id m_msg menubar_n=0 menubar_info=0
  menubar_prepare
  menubar_fail_warn && return 0
  while IFS='|' read -r m_st m_id m_msg; do
    [ -n "$m_st" ] || continue
    case "$m_st" in
      ok)
        menubar_n=$((menubar_n + 1))
        CHECKED=$((CHECKED + 1))
        pass "$m_msg"
        ;;
      drift)
        menubar_n=$((menubar_n + 1))
        CHECKED=$((CHECKED + 1))
        fixid menubar-allow
        bad "$m_msg"
        ;;
      info)
        menubar_info=$((menubar_info + 1))
        note "$m_msg"
        ;;
      warn)
        menubar_n=$((menubar_n + 1))
        CHECKED=$((CHECKED + 1))
        fixid menubar-allow
        warn "$m_msg"
        ;;
      *)
        menubar_n=$((menubar_n + 1))
        CHECKED=$((CHECKED + 1))
        fixid tooling
        warn "${m_msg:-$m_st}"
        ;;
    esac
  done <<MENUBAR_EOF
$MENUBAR_OUT
MENUBAR_EOF
  case "$MENUBAR_RC" in
    0|1) ;;
    *)
      CHECKED=$((CHECKED + 1))
      fixid tooling
      warn "Allow in the Menu Bar check failed or timed out (rc=$MENUBAR_RC) — settings not verified"
      ;;
  esac
  if [ "$menubar_n" -eq 0 ] && [ "$menubar_info" -eq 0 ] && [ "$MENUBAR_RC" -le 1 ]; then
    CHECKED=$((CHECKED + 1))
    fixid tooling
    warn "Allow in the Menu Bar check printed no results — settings not verified"
  fi
}

if [ "${MACCONFIG_CHECKS_DEFINE_ONLY:-}" = 1 ]; then
  return 0
fi

hdr "Allow in the Menu Bar"
check_step_menubar_third_party_hide
