# shellcheck shell=bash
#
# Read-only checks for scripts/manual-steps.sh: British input source, pointer
# size, GitHub CLI sign-in, 1Password CLI, and Spotlight app results.
# macconfig-check.sh prints that script's result in Manual steps
# and does not source this file.
# Each records R_STATUS (ok|warn|hand) and R_DETAIL via res(). Nothing here
# writes a setting, runs sudo, or opens the notification store. Callers wrap
# slow commands in with_timeout (defined by the caller).
#
# hand is "check by hand": not a warning (a preference that cannot be read,
# or Spotlight). A 1Password account added through the app is ok even when
# this terminal has not authorised `op whoami`.

# res is provided by scripts/manual-steps.sh. Define it when this file is
# sourced alone (the session-checks tests) so a check can record a status quietly.
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

# The keyboard layout must be British only. Press and Hold and similar
# non-layout entries are fine. Another keyboard layout is a warning.
# Nothing here is written.
check_input_british() {
  local src="" text="" key got=0 layouts name bad
  # Both keys hold input sources. On this Mac AppleSelectedInputSources can
  # fail to read while AppleEnabledInputSources still names the layout.
  # KeyboardLayout Name British is the layout. Press and Hold and other
  # non-layout entries are fine. Nothing here is written.
  if ! command -v defaults >/dev/null 2>&1; then
    res hand "could not read AppleEnabledInputSources or AppleSelectedInputSources"
    return
  fi
  for key in AppleEnabledInputSources AppleSelectedInputSources; do
    if text="$(defaults read com.apple.HIToolbox "$key" 2>/dev/null)"; then
      src="${src}
${text}"
      got=1
    fi
  done
  if [ "$got" = 0 ]; then
    res hand "could not read AppleEnabledInputSources or AppleSelectedInputSources"
    return
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

# The manual step is to turn on Integrate with 1Password CLI, then run
# `op signin` once in a terminal. This check never prompts and never runs
# `op signin`. `op whoami` only succeeds in a terminal that has already
# authorised, and that session expires, so a failure does not mean setup is
# missing. An account from `op account list` means the app integration is on:
# the step is done, and a new terminal asks to unlock on first use.
# The list body (account ids, emails, UUIDs, URLs) is piped into python,
# which prints only the number of accounts. It is not stored in a shell
# variable, a log, or a temp file, and stderr is discarded. The shell only
# keeps that count. No account is not set yet. SESSION_CHECKS_OP_APP
# overrides the app path in tests.
check_op_cli() {
  local app="${SESSION_CHECKS_OP_APP:-/Applications/1Password.app}"
  local n
  if [ ! -d "$app" ]; then res warn "1Password.app not installed (Fleet Self service)"; return; fi
  if ! command -v op >/dev/null 2>&1; then res warn "op CLI not installed (brew bundle)"; return; fi
  if with_timeout 8 op whoami </dev/null >/dev/null 2>&1; then
    res ok "signed in"
    return
  fi
  # python is the timed command. It moves to its own process group, pipes
  # `op account list` into a counter, and prints one integer. On the alarm
  # it kills that group, not the shell that started it.
  n="$(with_timeout 8 python3 -c '
import json, os, signal, subprocess
moved = False
try:
    os.setpgrp()
    moved = True
except Exception:
    moved = False
proc = None
def stop(_sig, _frm):
    if moved:
        try:
            os.killpg(0, signal.SIGKILL)
        except Exception:
            pass
    elif proc is not None:
        try:
            proc.kill()
        except Exception:
            pass
    raise SystemExit(142)
signal.signal(signal.SIGALRM, stop)
try:
    proc = subprocess.Popen(
        ["op", "account", "list", "--format=json"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
except Exception:
    print(0)
    raise SystemExit(0)
try:
    data = json.load(proc.stdout)
except Exception:
    data = None
try:
    proc.stdout.close()
except Exception:
    pass
try:
    proc.wait()
except Exception:
    pass
print(len(data) if isinstance(data, list) else 0)
' </dev/null 2>/dev/null || true)"
  case "$n" in
    ''|*[!0-9]*) n=0 ;;
  esac
  if [ "$n" -ge 1 ]; then
    res ok "set up (account added via the 1Password app); a new terminal asks to unlock on first use"
  else
    res warn "turn on Integrate with 1Password CLI in 1Password → Settings → Developer, then run op signin"
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
