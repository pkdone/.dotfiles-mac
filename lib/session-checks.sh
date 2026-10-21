# shellcheck shell=bash
#
# Read-only checks shared by scripts/manual-steps.sh and macconfig-check.sh:
# British input source, pointer size, GitHub CLI sign-in, 1Password CLI,
# App Store sign-in, and Spotlight app results.
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

# The selected input sources must be the British keyboard layout, plus any
# non-layout entries macOS keeps (Press and Hold, and similar). Another
# keyboard layout is a warning. Nothing here is written.
check_input_british() {
  local src layouts name bad
  if ! src="$(defaults read com.apple.HIToolbox AppleSelectedInputSources 2>/dev/null)"; then
    res hand "can't read the selected input sources"; return
  fi
  layouts="$(printf '%s\n' "$src" | awk '
    /InputSourceKind/ {
      kind = $0
      sub(/^.*InputSourceKind[[:space:]]*=[[:space:]]*/, "", kind)
      gsub(/[";]/, "", kind)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", kind)
    }
    /KeyboardLayout Name/ {
      name = $0
      sub(/^.*KeyboardLayout Name"[[:space:]]*=[[:space:]]*/, "", name)
      sub(/^.*KeyboardLayout Name[[:space:]]*=[[:space:]]*/, "", name)
      gsub(/[";]/, "", name)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
    }
    /^[[:space:]]*}[,;]?[[:space:]]*$/ {
      if (kind == "Keyboard Layout" || name != "") {
        if (name == "") name = "?"
        print name
      }
      kind = ""
      name = ""
    }
  ')"
  if [ -z "$layouts" ]; then
    res warn "no British keyboard layout is selected"
    return
  fi
  bad=""
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ "$name" != "British" ]; then
      bad="${bad:+$bad, }$name"
    fi
  done <<< "$layouts"
  if [ -n "$bad" ]; then
    res warn "keyboard layout is $bad (want only British)"
    return
  fi
  res ok "British keyboard layout only"
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

# `mas list` exits 0 when the App Store is signed in. It does not open the
# store. A timeout or a "not signed in" message is a warning.
check_app_store() {
  local out rc low
  if ! command -v mas >/dev/null 2>&1; then res warn "mas not installed (brew install mas)"; return; fi
  if out="$(with_timeout 20 mas list </dev/null 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    res ok "signed in to the App Store"
    return
  fi
  low="$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]')"
  case "$low" in
    *"not signed in"*) res warn "not signed in to the App Store" ;;
    *) res warn "mas list failed (${out:-exit $rc})" ;;
  esac
}

# Spotlight → Results from Apps. The apps that should be off are
# lib/spotlight-apps.list. The on/off toggles are not in a preference this
# check can read (EnabledPreferenceRules is the row list, and a row stays
# after the toggle is turned off), so the result is check by hand, not a
# warning. Nothing is written.
check_spotlight_results() {
  local py helper line status detail
  helper="$DOTDIR/lib/spotlight-rules.py"
  if [ ! -r "$helper" ] || [ ! -r "$DOTDIR/lib/spotlight-apps.list" ]; then
    res hand "Spotlight app list is missing"; return
  fi
  py="$(command -v python3 2>/dev/null || true)"
  if [ -z "$py" ]; then res hand "python3 not found"; return; fi
  line="$("$py" "$helper" --list "$DOTDIR/lib/spotlight-apps.list" 2>/dev/null || true)"
  status="${line%%|*}"
  detail="${line#*|}"
  case "$status" in
    ok) res ok "$detail" ;;
    warn) res warn "$detail" ;;
    *) res hand "${detail:-check System Settings → Spotlight → Results from Apps by hand}" ;;
  esac
}
