# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# scripts/manual-steps.sh calls check_step_tailscale_login (@macconfig:login-items).
# ---- 11. Login Items (Tailscale stays in Open at Login) ----
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

if [ "${MACCONFIG_CHECKS_DEFINE_ONLY:-}" = 1 ]; then
  return 0
fi

hdr "Login Items"
check_step_tailscale_login
