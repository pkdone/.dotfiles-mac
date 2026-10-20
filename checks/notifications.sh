# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 13e. Notifications (per-app Allow Notifications, check-only) ---------
# macOS 27 keeps per-app settings in the usernoted group plist. com.apple.ncprefs
# is gone. lib/notification-prefs.py reads that plist with plistlib and never
# writes it. Allow Notifications is flags bit ALLOW_NOTIFICATIONS_BIT in the
# helper. Apps that must be Off are lib/notifications-off.list (a warning, Needs
# Paul). A third-party bundle id that isn't there or in lib/notifications-reviewed.list
# is an info line. The same read reports org.hammerspoon.Hammerspoon's alert
# style (Alerts = ALERT_STYLE_BIT set and the banner bit clear). --fix does not
# touch this store. Manual step mode-hammerspoon-alerts points here.
hdr "Notifications"
NOTIF_HELPER="$DOTDIR/lib/notification-prefs.py"
CHECKED=$((CHECKED + 1))
fixid notifications
if [ ! -r "$NOTIF_HELPER" ]; then
  fixid repo-file
  warn "lib/notification-prefs.py missing — can't check notification settings"
elif [ ! -r "$DOTDIR/lib/notifications-off.list" ] || [ ! -r "$DOTDIR/lib/notifications-reviewed.list" ]; then
  fixid repo-file
  warn "notification lists missing — can't check Allow Notifications"
elif [ -z "$DOT_PYTHON" ]; then
  fixid tooling
  warn "no python3 — can't check notification settings"
else
  if notif_out="$(with_timeout 20 "$DOT_PYTHON" "$NOTIF_HELPER" </dev/null 2>&1)"; then
    notif_rc=0
  else
    notif_rc=$?
  fi
  notif_n=0
  while IFS='|' read -r n_st _ n_msg; do
    [ -n "$n_st" ] || continue
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
$notif_out
NOTIF_EOF
  case "$notif_rc" in
    0|1) ;;
    *) fixid tooling; warn "notification check failed or timed out (rc=$notif_rc) — settings not verified" ;;
  esac
  if [ "$notif_n" -eq 0 ] && [ "$notif_rc" -le 1 ]; then
    case "$notif_out" in
      error\|*) ;;
      *) fixid tooling; warn "notification check printed no results — settings not verified" ;;
    esac
  fi
fi
