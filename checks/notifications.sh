# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# scripts/manual-steps.sh calls check_step_notifications_apps and
# check_step_mode_hammerspoon_alerts (@macconfig:notifications).
# ---- 13e. Notifications (per-app Allow Notifications, check-only) ---------
# macOS 27 keeps per-app settings in the usernoted group plist. com.apple.ncprefs
# is gone. lib/notification-prefs.py reads that plist with plistlib and never
# writes it. Allow Notifications is flags bit ALLOW_NOTIFICATIONS_BIT in the
# helper. Apps that must be Off are lib/notifications-off.list (a warning, Needs
# Paul). A third-party bundle id that isn't there or in lib/notifications-reviewed.list
# is an info line. The same read reports org.hammerspoon.Hammerspoon's alert
# style (Alerts = ALERT_STYLE_BIT set and the banner bit clear). --fix does not
# touch this store. Manual step mode-hammerspoon-alerts points here.
notif_prepare() {
  [ "${NOTIF_PREPARED:-}" = 1 ] && return 0
  NOTIF_PREPARED=1
  NOTIF_HELPER="$DOTDIR/lib/notification-prefs.py"
  NOTIF_OUT=""
  NOTIF_RC=0
  NOTIF_FAIL=""
  NOTIF_FAIL_ID=notifications
  if [ ! -r "$NOTIF_HELPER" ]; then
    NOTIF_FAIL="lib/notification-prefs.py missing — can't check notification settings"
    NOTIF_FAIL_ID=repo-file
  elif [ ! -r "$DOTDIR/lib/notifications-off.list" ] || [ ! -r "$DOTDIR/lib/notifications-reviewed.list" ]; then
    NOTIF_FAIL="notification lists missing — can't check Allow Notifications"
    NOTIF_FAIL_ID=repo-file
  elif [ -z "$DOT_PYTHON" ]; then
    NOTIF_FAIL="no python3 — can't check notification settings"
    NOTIF_FAIL_ID=tooling
  else
    if NOTIF_OUT="$(with_timeout 20 "$DOT_PYTHON" "$NOTIF_HELPER" </dev/null 2>&1)"; then
      NOTIF_RC=0
    else
      NOTIF_RC=$?
    fi
  fi
}

notif_fail_warn() {
  [ -n "${NOTIF_FAIL:-}" ] || return 1
  if [ "${NOTIF_FAIL_WARNED:-}" = 1 ]; then return 0; fi
  NOTIF_FAIL_WARNED=1
  fixid "$NOTIF_FAIL_ID"
  warn "$NOTIF_FAIL"
  return 0
}

check_step_notifications_apps() {
  local n_st n_id n_msg notif_n=0
  notif_prepare
  notif_fail_warn && return 0
  while IFS='|' read -r n_st n_id n_msg; do
    [ -n "$n_st" ] || continue
    case "$n_id" in org.hammerspoon.Hammerspoon) continue ;; esac
    case "$n_st" in
      ok)
        notif_n=$((notif_n + 1))
        [ "$notif_n" -eq 1 ] || CHECKED=$((CHECKED + 1))
        pass "$n_msg"
        ;;
      warn)
        notif_n=$((notif_n + 1))
        [ "$notif_n" -eq 1 ] || CHECKED=$((CHECKED + 1))
        fixid notifications
        warn "$n_msg"
        ;;
      info) info "$n_msg" ;;
      *)
        fixid tooling
        warn "${n_msg:-$n_st}"
        ;;
    esac
  done <<NOTIF_EOF
$NOTIF_OUT
NOTIF_EOF
  case "$NOTIF_RC" in
    0|1) ;;
    *)
      fixid tooling
      warn "notification check failed or timed out (rc=$NOTIF_RC) — settings not verified"
      ;;
  esac
  if [ "$notif_n" -eq 0 ] && [ "$NOTIF_RC" -le 1 ]; then
    case "$NOTIF_OUT" in
      error\|*) ;;
      *)
        fixid tooling
        warn "notification check printed no results — settings not verified"
        ;;
    esac
  fi
}

check_step_mode_hammerspoon_alerts() {
  local n_st n_id n_msg
  notif_prepare
  notif_fail_warn && return 0
  while IFS='|' read -r n_st n_id n_msg; do
    [ -n "$n_st" ] || continue
    case "$n_id" in org.hammerspoon.Hammerspoon) ;; *) continue ;; esac
    case "$n_st" in
      ok)
        CHECKED=$((CHECKED + 1))
        pass "$n_msg"
        ;;
      warn)
        CHECKED=$((CHECKED + 1))
        fixid notifications
        warn "$n_msg"
        ;;
      info) info "$n_msg" ;;
      *)
        fixid tooling
        warn "${n_msg:-$n_st}"
        ;;
    esac
  done <<NOTIF_EOF
$NOTIF_OUT
NOTIF_EOF
}

if [ "${MACCONFIG_CHECKS_DEFINE_ONLY:-}" = 1 ]; then
  return 0
fi

hdr "Notifications"
CHECKED=$((CHECKED + 1))
check_step_notifications_apps
check_step_mode_hammerspoon_alerts
