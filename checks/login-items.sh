# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# scripts/manual-steps.sh calls check_step_tailscale_login (@macconfig:login-items).
# The Tailscale heading below is the running / exit-node check, and Allow
# Local Network Access when an exit node is selected. It is its own heading
# so a warning there does not change the Login Items rollup.
# ---- 11. Login Items (Tailscale stays in Open at Login) ----
# shellcheck source=../lib/safe-fixers.sh disable=SC1091
. "$DOTDIR/lib/safe-fixers.sh"
# Tailscale has no launch-at-login switch of its own. Paul adds
# /Applications/Tailscale.app under Open at Login. This only reads.
# The repo does not add login items (osascript "make login item" is not
# how the other apps get there, and it needs an Automation prompt).
# Missing app: leave it alone. The Fleet check already reports that.
TAILSCALE_LOGIN_HOW="System Settings → General → Login Items & Extensions → under Open at Login click + → Applications → Tailscale → Open"

tailscale_login_named() { # comma-separated System Events names
  case ", $1," in
    *", Tailscale,"*) return 0 ;;
  esac
  return 1
}

check_step_tailscale_login() {
  local app bid classic classic_rc btm_raw btm_rc btm_st
  fixid login-items
  app="${TAILSCALE_APP_PATH:-/Applications/Tailscale.app}"
  if [ ! -d "$app" ]; then
    # Not installed: Open at Login does not apply. The Fleet check reports
    # the missing app. skip prints the info line and does not count it.
    skip "Tailscale is not installed yet, so Open at Login is left alone"
    return 0
  fi
  bid=""
  if [ -n "${DOT_PYTHON:-}" ] && [ -r "$app/Contents/Info.plist" ]; then
    bid="$("$DOT_PYTHON" -c 'import plistlib,sys
print(plistlib.load(open(sys.argv[1], "rb")).get("CFBundleIdentifier") or "")' \
      "$app/Contents/Info.plist" 2>/dev/null || true)"
  fi
  [ -n "$bid" ] || bid="io.tailscale.ipn.macsys"
  classic=""
  classic_rc=0
  if classic="$(with_timeout 8 osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null)"; then
    classic_rc=0
  else
    classic_rc=$?
    classic=""
  fi
  if [ "$classic_rc" -eq 0 ] && tailscale_login_named "$classic"; then
    CHECKED=$((CHECKED + 1))
    pass "Tailscale is in Open at Login"
    return 0
  fi
  btm_st=""
  if [ -n "${DOT_PYTHON:-}" ] && [ -r "$DOTDIR/lib/btm-login-items.py" ]; then
    btm_raw="$("$DOT_PYTHON" "$DOTDIR/lib/btm-login-items.py" "$bid" 2>/dev/null)" && btm_rc=0 || btm_rc=$?
    btm_st="$(printf '%s\n' "$btm_raw" | awk -F= -v b="$bid" '$1==b { print $2; exit }')"
    case "$btm_st" in
      enabled)
        CHECKED=$((CHECKED + 1))
        pass "Tailscale is in Open at Login"
        return 0
        ;;
    esac
    if [ "$btm_rc" = 3 ]; then
      btm_st="unreadable"
    fi
  fi
  # A successful name list that does not contain Tailscale means it is absent.
  # BTM "disabled" means the app record is off. A failed name list plus a
  # missing or unreadable store is not proof, so that stays by hand.
  if [ "$classic_rc" -eq 0 ] || [ "$btm_st" = "disabled" ]; then
    CHECKED=$((CHECKED + 1))
    warn "Tailscale is not in Open at Login — $TAILSCALE_LOGIN_HOW"
    return 0
  fi
  # Could not be read: still by hand, so info counts it there. It is not
  # part of the ok total.
  info "Open at Login could not be read, so Tailscale stays by hand — $TAILSCALE_LOGIN_HOW"
}

# Tailscale should be running with an exit node selected, and Allow Local
# Network Access should be on once a node is selected. Any selected node
# passes, including one managed policy chose. Not installed, not signed in,
# stopped, still starting, unreadable, or running with no exit node is a
# warning: those do not fail macconfig. ExitNodeAllowLANAccess false is a
# warning only when an exit node is selected. It does not fail the run.
# When no exit node is selected, a false value is not that warning. The
# message is one line and does not include node ids, addresses, or keys.
# safe_tailscale_exit is the SAFE fixer for both lines.
check_tailscale_exit() {
  local bin="" state=""
  fixid tailscale-exit
  CHECKED=$((CHECKED + 1))
  if ! bin="$(tailscale_bin)"; then
    warn "Tailscale is not installed — install it from Fleet Self service (Fleet Desktop menu bar → My device → Self service). macconfig --fix does not install it"
    return 0
  fi
  state="$(tailscale_exit_probe "$bin")"
  case "$state" in
    running-exit)
      pass "Tailscale is running with an exit node selected"
      ;;
    logged-out)
      warn "Tailscale is not signed in — open it and sign in (manual step tailscale-signin). macconfig --fix does not sign in"
      ;;
    starting)
      warn "Tailscale is still starting. macconfig --fix leaves it alone until it is running"
      ;;
    stopped)
      warn "Tailscale is signed in but not running. macconfig --fix turns it on and selects the recommended exit node when none is selected"
      ;;
    running-none)
      warn "Tailscale is running with no exit node selected. macconfig --fix selects the recommended one. If managed policy blocks the change, this stays a warning, and any selected exit node counts"
      ;;
    *)
      warn "Tailscale status could not be read. Leave it if it is offline; macconfig --fix tries again and does not fail the run"
      ;;
  esac
}

# Allow Local Network Access (ExitNodeAllowLANAccess in tailscale debug prefs).
# Passes when the value is true. When an exit node is selected and the value
# is false, or the prefs cannot be read, that is a warning on the same
# tailscale-exit row. It does not fail macconfig. When no exit node is
# selected, a false or unreadable value is not this warning: the exit-node
# line above is the one that applies. A missing CLI or a signed-out app is
# already that other warning, so this check stays quiet. The tag is set
# on the line before pass or warn.
check_tailscale_lan() {
  local bin="" state="" lan=""
  if ! bin="$(tailscale_bin)"; then
    return 0
  fi
  state="$(tailscale_exit_probe "$bin")"
  case "$state" in
    running-exit|running-none|stopped) ;;
    *) return 0 ;;
  esac
  lan="$(tailscale_lan_probe "$bin")"
  if [ "$lan" = yes ]; then
    CHECKED=$((CHECKED + 1))
    fixid tailscale-exit
    pass "Tailscale Allow Local Network Access is on"
    return 0
  fi
  if [ "$state" != running-exit ]; then
    return 0
  fi
  CHECKED=$((CHECKED + 1))
  fixid tailscale-exit
  if [ "$lan" = no ]; then
    warn "Tailscale is using an exit node with Allow Local Network Access off. macconfig --fix turns it on (tailscale set --exit-node-allow-lan-access=true). If managed policy blocks the change, this stays a warning"
  else
    warn "Tailscale Allow Local Network Access could not be read. macconfig --fix tries again and does not fail the run"
  fi
}

if [ "${MACCONFIG_CHECKS_DEFINE_ONLY:-}" = 1 ]; then
  return 0
fi

hdr "Login Items"
check_step_tailscale_login
hdr "Tailscale"
check_tailscale_exit
check_tailscale_lan
