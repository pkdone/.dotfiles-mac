# shellcheck shell=bash
#
# safe-fixers.sh — the SAFE fixers bootstrap and `macconfig-check.sh --fix` share.
# Sourced, not executed. One implementation of each setter, so a fresh Mac
# (install.sh / dock.sh) and a later --fix cannot drift.
#
#   safe_start_hammerspoon   open -g -a Hammerspoon, only if installed and not running
#   safe_apply_desktops      lib/desktop-bindings.py --apply (backup, app-bindings,
#                            restart Dock only if a pin changed)
#   safe_install_origin      Cursor's origin installer, only when
#                            $HOME/.local/bin/origin is missing or not an
#                            executable file. No sudo, no version pin.
#                            Copies the repo gitconfig and writes it back
#                            if that run changes it. Only that file.
#   safe_tailscale_exit      Turn Tailscale on when it is signed in but
#                            stopped, and select the recommended exit node
#                            when none is selected. An exit node that is
#                            already selected is left alone. No sudo, no
#                            sign-in, no Fleet or MDM change.
#
# DRY_RUN=1 prints what would happen and changes nothing. No sudo.

SAFE_FIXERS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Start Hammerspoon when the app is installed and the process is not already
# running. Prints one line. Returns 0 (started, already running, or dry-run),
# 1 (open did not start it), or 2 (not installed).
#
# SAFE_HAMMERSPOON_DESCRIBE=1 is install.sh --dry-run: the Brewfile cask would
# be installed first, so a missing app still gets the would-start line.
# HAMMERSPOON_APP overrides the install check (tests). The open command stays
# `open -g -a Hammerspoon`, the same one macconfig --fix has always used.
safe_start_hammerspoon() {
  local app i=0
  app="${HAMMERSPOON_APP:-/Applications/Hammerspoon.app}"
  if [ ! -d "$app" ]; then
    if [ "${SAFE_HAMMERSPOON_DESCRIBE:-0}" = 1 ]; then
      echo "would start Hammerspoon (open -g -a Hammerspoon) if it is installed and not running"
      return 0
    fi
    echo "Hammerspoon.app not installed — run brewsync"
    return 2
  fi
  if pgrep -xq Hammerspoon; then
    echo "Hammerspoon already running"
    return 0
  fi
  if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "would start Hammerspoon (open -g -a Hammerspoon)"
    return 0
  fi
  open -g -a Hammerspoon 2>/dev/null || true
  while [ "$i" -lt 15 ] && ! pgrep -xq Hammerspoon; do
    sleep 1
    i=$((i + 1))
  done
  if pgrep -xq Hammerspoon; then
    echo "started Hammerspoon"
    return 0
  fi
  echo "open -a Hammerspoon didn't start it"
  return 1
}

# Install the Cursor origin CLI when the binary is missing or not executable.
# Homebrew has no formula. The official installer writes $HOME/.local/bin/origin
# and does not use sudo. An executable file is left alone, so a later run does
# not download and does not pin a version.
#
# The published installer (https://downloads.cursor.com/origin/install.sh) has
# no option to skip git config. Its variables are ORIGIN_INSTALL_CHANNEL,
# ORIGIN_INSTALL_DIR, ORIGIN_BIN_DIR, XDG_CONFIG_HOME, and the legacy CO_*
# names for the first three. On Paul's Mac the installer rewrote ~/.gitconfig:
# both origin credential helpers became an absolute home path, and the blank
# helper lines moved. That path is a symlink to this repo's gitconfig, so the
# tracked file changed. Copy this one file before the installer and write those
# bytes back only when they differ. Do not restore any other path.
#
# ORIGIN_BIN overrides the path (tests). ORIGIN_INSTALL_URL overrides the
# installer URL. ORIGIN_GITCONFIG overrides the repo gitconfig path (tests).
# Prints one line. Returns 0 (already installed, installed, or dry-run) or 1
# (the installer failed, it finished without an executable, or gitconfig could
# not be snapshotted or restored).
safe_install_origin() {
  local bin url shown gitconfig snap rc
  bin="${ORIGIN_BIN:-$HOME/.local/bin/origin}"
  url="${ORIGIN_INSTALL_URL:-https://downloads.cursor.com/origin/install.sh}"
  gitconfig="${ORIGIN_GITCONFIG:-$SAFE_FIXERS_ROOT/gitconfig}"
  shown="$bin"
  case "$shown" in
    "$HOME"/*) shown="~${shown#"$HOME"}" ;;
  esac
  if [ -f "$bin" ] && [ -x "$bin" ]; then
    echo "origin already installed ($shown)"
    return 0
  fi
  if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "would install origin (curl -fsSL $url | sh) because $shown is missing or not executable"
    return 0
  fi

  # Callers run this under `||`, which turns set -e off for the whole function.
  # A failed snapshot must stop the installer: there would be nothing to put back.
  snap=""
  if [ -f "$gitconfig" ]; then
    snap="$(mktemp)" || snap=""
    if [ -z "$snap" ] || ! cat "$gitconfig" > "$snap"; then
      rm -f "$snap"
      echo "could not snapshot gitconfig ($gitconfig)"
      return 1
    fi
  fi

  rc=0
  if curl -fsSL "$url" | sh; then
    if [ -f "$bin" ] && [ -x "$bin" ]; then
      echo "installed origin ($shown)"
    else
      echo "origin installer finished but $shown is still missing or not executable"
      rc=1
    fi
  else
    echo "origin installer failed ($shown)"
    rc=1
  fi

  if [ -n "$snap" ]; then
    if [ ! -f "$gitconfig" ] || ! cmp -s "$snap" "$gitconfig"; then
      if ! cat "$snap" > "$gitconfig"; then
        echo "could not restore gitconfig ($gitconfig); snapshot left at $snap"
        return 1
      fi
    fi
    rm -f "$snap"
  fi
  return "$rc"
}

# Apply lib/desktop-bindings.list. Extra arguments go to desktop-bindings.py
# before the list path (`--dry-run`, `--only id,id`). Prints the helper's
# status|bundle|message lines. Returns its status, or 2 when python3 is missing
# (one fail line per --only id, or a single fail line when applying the list).
safe_apply_desktops() {
  local py only="" arg prev=""
  for arg in "$@"; do
    if [ "$prev" = "--only" ]; then
      only="$arg"
    fi
    prev="$arg"
  done
  # shellcheck source=defaults-lib.sh disable=SC1091
  . "$SAFE_FIXERS_ROOT/lib/defaults-lib.sh"
  if ! py="$(dot_python)"; then
    if [ -n "$only" ]; then
      while IFS= read -r arg; do
        [ -n "$arg" ] || continue
        printf 'fail|%s|python3 not found — desktop assignment not changed\n' "$arg"
      done < <(printf '%s\n' "$only" | tr ',' '\n')
    else
      printf 'fail||python3 not found — desktop assignment not changed\n'
    fi
    return 2
  fi
  "$py" "$SAFE_FIXERS_ROOT/lib/desktop-bindings.py" --apply "$@" "$SAFE_FIXERS_ROOT/lib/desktop-bindings.list"
}

# Bound a command. macOS has no timeout(1). perl's alarm survives exec.
# Status 142 when the alarm fires. Callers must tolerate a non-zero status.
safe_run_timeout() { # secs cmd...
  local secs="$1"
  shift
  perl -e '$t = shift @ARGV; alarm $t; exec { $ARGV[0] } @ARGV or exit 127' "$secs" "$@"
}

# The Tailscale CLI. TAILSCALE_BIN is the test override: when it is set, the
# app bundle and PATH are not consulted, so a missing path stays missing.
# Otherwise the standalone app binary, then `tailscale` on PATH.
# Prints the path. Status 1 when there is nothing executable to run.
tailscale_bin() {
  local bin=""
  if [ -n "${TAILSCALE_BIN+x}" ]; then
    bin="$TAILSCALE_BIN"
  elif [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]; then
    bin="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
  elif command -v tailscale >/dev/null 2>&1; then
    bin="$(command -v tailscale)"
  fi
  if [ -n "$bin" ] && [ -x "$bin" ]; then
    printf '%s\n' "$bin"
    return 0
  fi
  return 1
}

# Run the CLI in CLI mode so the app binary does not open a window.
# stdout only. stderr is dropped: it can carry an auth URL.
tailscale_cli() { # bin args...
  local bin="$1"
  shift
  TAILSCALE_BE_CLI=1 safe_run_timeout 15 "$bin" "$@" 2>/dev/null
}

# Read one JSON blob from stdin. mode is status or prefs.
# status prints "yes|Running" (exit node selected in ExitNodeStatus | BackendState) or "bad".
# prefs prints "yes|no" (LoggedOut | an exit node is selected) or "bad".
# Selected means ExitNodeID, ExitNodeIP, or AutoExitNode is a non-empty string.
# Node ids, addresses, keys, and account names are not printed.
tailscale_parse_json() { # mode
  local py
  py="$(command -v python3 2>/dev/null || true)"
  if [ -z "$py" ]; then
    printf 'bad\n'
    return 0
  fi
  "$py" -c '
import json, sys
mode = sys.argv[1]
raw = sys.stdin.read()
start = raw.find("{")
end = raw.rfind("}")
if start < 0 or end < start:
    print("bad")
    raise SystemExit(0)
try:
    data = json.loads(raw[start:end + 1])
except Exception:
    print("bad")
    raise SystemExit(0)
if not isinstance(data, dict):
    print("bad")
    raise SystemExit(0)

def flag(value):
    return "yes" if value else "no"

if mode == "status":
    state = data.get("BackendState")
    state = state if isinstance(state, str) else ""
    state = state.replace("|", "/")
    ex = data.get("ExitNodeStatus")
    selected = isinstance(ex, dict) and len(ex) > 0
    print(flag(selected) + "|" + state)
elif mode == "prefs":
    logged = data.get("LoggedOut") is True
    has = False
    for item in (data.get("ExitNodeID"), data.get("ExitNodeIP"), data.get("AutoExitNode")):
        if isinstance(item, str) and item.strip() != "":
            has = True
    print(flag(logged) + "|" + flag(has))
else:
    print("bad")
' "$1" 2>/dev/null || printf 'bad\n'
}

# One token, no secrets:
#   missing is not used here (the caller checks tailscale_bin)
#   unreadable | logged-out | starting | stopped | running-exit | running-none
# running-exit is Running plus any selected exit node. The node is not named.
tailscale_exit_probe() { # bin
  local bin="$1" status parsed exit_on state prefs logged has_exit
  status="$(tailscale_cli "$bin" status --json || true)"
  parsed="$(printf '%s' "$status" | tailscale_parse_json status || true)"
  if [ -z "$parsed" ] || [ "$parsed" = bad ]; then
    printf 'unreadable\n'
    return 0
  fi
  exit_on="${parsed%%|*}"
  state="${parsed#*|}"
  if [ "$exit_on" != yes ] && [ "$exit_on" != no ]; then
    printf 'unreadable\n'
    return 0
  fi
  case "$state" in
    NeedsLogin|NeedsMachineAuth)
      printf 'logged-out\n'
      return 0
      ;;
    Starting)
      printf 'starting\n'
      return 0
      ;;
    Running|Stopped) ;;
    *)
      printf 'unreadable\n'
      return 0
      ;;
  esac
  if [ "$state" = Running ] && [ "$exit_on" = yes ]; then
    printf 'running-exit\n'
    return 0
  fi
  prefs="$(tailscale_cli "$bin" debug prefs || true)"
  parsed="$(printf '%s' "$prefs" | tailscale_parse_json prefs || true)"
  logged="${parsed%%|*}"
  has_exit="${parsed#*|}"
  if [ "$logged" != yes ] && [ "$logged" != no ]; then
    if [ "$state" = Running ]; then
      printf 'running-none\n'
    else
      printf 'unreadable\n'
    fi
    return 0
  fi
  # Running wins over a stale LoggedOut flag. Stopped plus LoggedOut is signed out.
  if [ "$logged" = yes ] && [ "$state" != Running ]; then
    printf 'logged-out\n'
    return 0
  fi
  if [ "$state" = Stopped ]; then
    printf 'stopped\n'
    return 0
  fi
  if [ "$has_exit" = yes ]; then
    printf 'running-exit\n'
  else
    printf 'running-none\n'
  fi
}

# A value that can be passed to --exit-node. Rejects blanks, flags, and
# anything that is not a hostname, IP, or auto:any.
tailscale_choice_ok() {
  case "$1" in
    ""|-*|*[!A-Za-z0-9._:-]*) return 1 ;;
  esac
  return 0
}

# The recommended exit node, printed as one token. Status 1 when there is
# none. auto:any when `tailscale set --help` offers it: that is Tailscale's
# own "keep using the recommended exit node" switch. Otherwise the hostname
# from `tailscale exit-node suggest` (the "Suggested exit node:" line, with
# one trailing DNS dot removed). The prose `--exit-node=` example is only
# used when that line is missing. The token is not an account or a key.
tailscale_exit_choice() { # bin
  local bin="$1" help suggest rest line token
  help="$(TAILSCALE_BE_CLI=1 safe_run_timeout 10 "$bin" set --help 2>&1 || true)"
  case "$help" in
    *auto:any*)
      printf '%s\n' "auto:any"
      return 0
      ;;
  esac
  suggest="$(tailscale_cli "$bin" exit-node suggest || true)"
  token=""
  rest="$suggest"
  while [ -n "$rest" ]; do
    line="${rest%%$'\n'*}"
    case "$rest" in
      *$'\n'*) rest="${rest#*$'\n'}" ;;
      *) rest="" ;;
    esac
    line="${line%$'\r'}"
    case "$line" in
      "Suggested exit node:"*)
        token="${line#Suggested exit node:}"
        token="${token#"${token%%[![:space:]]*}"}"
        token="${token%"${token##*[![:space:]]}"}"
        token="${token%.}"
        ;;
    esac
  done
  if ! tailscale_choice_ok "$token"; then
    token=""
    line="$(printf '%s' "$suggest" | tr -d '\r')"
    case "$line" in
      *$'\n'*) ;;
      *) token="$line" ;;
    esac
  fi
  if ! tailscale_choice_ok "$token"; then
    token="$(printf '%s\n' "$suggest" | sed -n 's/.*--exit-node=\([A-Za-z0-9._:-][A-Za-z0-9._:-]*\).*/\1/p' | head -n 1)"
  fi
  if ! tailscale_choice_ok "$token"; then
    return 1
  fi
  printf '%s\n' "$token"
}

# Bring a signed-in, stopped Tailscale up. Does not pass --exit-node, so a
# policy that refuses an exit-node change can still leave the tunnel up.
# --timeout=15s when the CLI documents it. Status is the CLI's status.
tailscale_up() { # bin
  local bin="$1" help
  help="$(TAILSCALE_BE_CLI=1 safe_run_timeout 10 "$bin" up --help 2>&1 || true)"
  case "$help" in
    *--timeout*)
      TAILSCALE_BE_CLI=1 safe_run_timeout 25 "$bin" up --timeout=15s >/dev/null 2>&1
      ;;
    *)
      TAILSCALE_BE_CLI=1 safe_run_timeout 25 "$bin" up >/dev/null 2>&1
      ;;
  esac
}

# Select the recommended exit node. Status is the CLI's status. stderr is
# discarded so an auth URL is not printed.
tailscale_set_exit() { # bin choice
  TAILSCALE_BE_CLI=1 safe_run_timeout 20 "$1" set --exit-node="$2" >/dev/null 2>&1
}

# Turn Tailscale on when it is signed in but stopped, and select the
# recommended exit node when none is selected. A node that is already
# selected is left alone: managed policy may refuse a different one, and
# any selected exit node is the desired state.
#
# Prints one line. Does not print node ids, addresses, keys, or auth URLs.
# Does not use sudo, does not sign in, and does not change Fleet or MDM.
# Returns 0 when Tailscale is already in that state, the change was applied,
# or a dry run would apply it. Returns 2 when nothing was changed (not
# installed, not signed in, unreadable, still starting, offline, no
# suggestion, or the set was refused).
#
# Callers that must keep going (install.sh) catch this status. A missing
# CLI does not fail bootstrap.
safe_tailscale_exit() {
  local bin="" state="" choice=""
  if ! bin="$(tailscale_bin)"; then
    if [ "${DRY_RUN:-0}" = 1 ]; then
      echo "would leave Tailscale alone (not installed or the CLI can't be run)"
    else
      echo "Tailscale is not installed or the CLI can't be run — install it from Fleet Self service. Not changed"
    fi
    return 2
  fi
  state="$(tailscale_exit_probe "$bin")"
  case "$state" in
    running-exit)
      echo "Tailscale is already running with an exit node selected"
      return 0
      ;;
    logged-out)
      echo "Tailscale is not signed in — manual step tailscale-signin. Not changed"
      return 2
      ;;
    unreadable|starting)
      echo "Tailscale status could not be read or it is still starting. Not changed"
      return 2
      ;;
    stopped|running-none) ;;
    *)
      echo "Tailscale status could not be read. Not changed"
      return 2
      ;;
  esac
  if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "would turn Tailscale on if it is stopped and select the recommended exit node (tailscale up or tailscale set --exit-node, no sudo)"
    return 0
  fi
  if [ "$state" = stopped ]; then
    if ! tailscale_up "$bin"; then
      echo "Tailscale could not be turned on (it may be offline). Not changed"
      return 2
    fi
    state="$(tailscale_exit_probe "$bin")"
    case "$state" in
      running-exit)
        echo "Tailscale is running with an exit node selected"
        return 0
        ;;
      running-none) ;;
      logged-out)
        echo "Tailscale is not signed in — manual step tailscale-signin. Not changed"
        return 2
        ;;
      *)
        echo "Tailscale did not stay running. Not changed"
        return 2
        ;;
    esac
  fi
  if ! choice="$(tailscale_exit_choice "$bin")"; then
    echo "no recommended exit node from tailscale exit-node suggest. Not changed"
    return 2
  fi
  if ! tailscale_set_exit "$bin" "$choice"; then
    echo "could not select the recommended exit node. Managed policy may block the change. Any exit node already selected still counts. Not changed"
    return 2
  fi
  state="$(tailscale_exit_probe "$bin")"
  case "$state" in
    running-exit)
      echo "Tailscale is running with an exit node selected"
      return 0
      ;;
  esac
  echo "the exit-node change did not stick. Managed policy may block it. Any exit node already selected still counts"
  return 2
}
