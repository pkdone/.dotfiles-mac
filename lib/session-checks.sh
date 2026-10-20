# shellcheck shell=bash
#
# Read-only checks shared by scripts/manual-steps.sh and macconfig-check.sh:
# British input source, pointer size, GitHub CLI sign-in, and 1Password CLI.
# Each records R_STATUS (ok|warn|hand) and R_DETAIL via res(). Nothing here
# writes a setting, runs sudo, or opens the notification store. Callers wrap
# slow commands in with_timeout (defined by the caller).
#
# hand is "check by hand": not a warning. 1Password installed but not signed
# in (it needs an unlock, or this session was never authorised) is hand.

# res is provided by scripts/manual-steps.sh. Define it when this file is
# sourced alone (macconfig-check.sh) so a check can record a status quietly.
if ! declare -F res >/dev/null 2>&1; then
  # Callers read R_STATUS and R_DETAIL after the check returns.
  # shellcheck disable=SC2034
  res() { R_STATUS="$1"; R_DETAIL="$2"; }
fi

# Normal is 1.0; "one notch above" lands around 1.4, so accept 1.2-2.0.
check_pointer_size() {
  local v
  if ! defaults read com.apple.universalaccess >/dev/null 2>&1; then res hand "can't read com.apple.universalaccess"; return; fi
  if ! v="$(defaults read com.apple.universalaccess mouseDriverCursorSize 2>/dev/null)"; then
    res warn "Normal (not set; want one notch above)"; return
  fi
  if awk -v v="$v" 'BEGIN { exit !(v >= 1.2 && v <= 2.0) }'; then
    res ok "size $(printf '%.2f' "$v")"
  else
    res warn "size $(printf '%.2f' "$v") (want about 1.4: one notch above Normal)"
  fi
}

check_input_british() {
  local src
  if ! src="$(defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null)"; then
    res hand "can't read input sources"; return
  fi
  if printf '%s\n' "$src" | grep -Eq '"KeyboardLayout Name" = British;'; then
    res ok "British enabled"
  else
    res warn "British layout not enabled"
  fi
}

# `op whoami` never prompts: with the app integration it only reports an account this
# terminal session has already authorised. Success proves the integration works.
# Installed but not signed in (an unlock, or this session was never authorised)
# is check by hand, not a warning. SESSION_CHECKS_OP_APP overrides the app path
# in tests.
check_op_cli() {
  local app="${SESSION_CHECKS_OP_APP:-/Applications/1Password.app}"
  if [ ! -d "$app" ]; then res warn "1Password.app not installed (Iru Self Service)"; return; fi
  if ! command -v op >/dev/null 2>&1; then res warn "op CLI not installed (brew bundle)"; return; fi
  if with_timeout 8 op whoami </dev/null >/dev/null 2>&1; then
    res ok "op whoami works through the app"
  else
    res hand "installed but not signed in (an unlock may be required); run op whoami in a terminal to confirm"
  fi
}

check_gh_auth() {
  if ! command -v gh >/dev/null 2>&1; then res warn "gh not installed (brew install gh)"; return; fi
  if with_timeout 15 gh auth status --hostname github.com </dev/null >/dev/null 2>&1; then
    res ok "signed in to github.com"
  else
    res warn "not signed in (or GitHub unreachable): gh auth login"
  fi
}
