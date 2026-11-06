#!/usr/bin/env bash
# SC2317: hdr/pass/warn/bad/skip/info/fixid inside the section subshell are
# stubs the sourced checks/login-items.sh calls.
# shellcheck disable=SC2317
#
# Tailscale should be running with an exit node selected, and Allow Local
# Network Access should be on once a node is selected. Any selected node
# passes. The fixer turns a signed-in stopped CLI on, selects the
# recommended node when none is selected, and turns on Allow Local Network
# Access when an exit node is selected and that pref is false. A missing
# CLI, a signed-out CLI, and a refused set are warnings, not drift, and
# they do not fail install. When no exit node is selected, a false pref
# is not the Allow Local Network Access warning.
# The stub is the only tailscale this file runs.
# Run: ./tests/tailscale-exit.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hermetic.sh disable=SC1091
. "$DIR/tests/hermetic.sh"

pass=0
fail=0
eq() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
has() {
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;; esac
}
miss() {
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;;
    *) pass=$((pass + 1)) ;; esac
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
safe="$(hermetic_safe_root)"
bin="$tmp/bin"
mkdir -p "$bin"
log="$tmp/tailscale.log"
status_file="$tmp/status.json"
prefs_file="$tmp/prefs.json"
: > "$log"

cat > "$bin/tailscale" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${TAILSCALE_LOG:?}"
printf 'BE=%s\n' "${TAILSCALE_BE_CLI-}" >> "${TAILSCALE_LOG:?}"
if [ "$1" = set ] && [ "$2" = --help ]; then
  printf '%s\n' "${TAILSCALE_SET_HELP-}"
  exit 0
fi
if [ "$1" = up ] && [ "$2" = --help ]; then
  printf '%s\n' "${TAILSCALE_UP_HELP-}"
  exit 0
fi
if [ "$1" = status ]; then
  cat "${TAILSCALE_STATUS_FILE:?}" 2>/dev/null || exit 1
  exit 0
fi
if [ "$1" = debug ] && [ "$2" = prefs ]; then
  cat "${TAILSCALE_PREFS_FILE:?}" 2>/dev/null || exit 1
  exit 0
fi
if [ "$1" = exit-node ] && [ "$2" = suggest ]; then
  printf '%s\n' "${TAILSCALE_SUGGEST-}"
  exit 0
fi
if [ "$1" = set ] && [ "$2" = "--exit-node-allow-lan-access=true" ]; then
  if [ "${TAILSCALE_LAN_RC:-0}" != 0 ]; then
    printf '%s\n' "${TAILSCALE_LAN_ERR-}" >&2
    exit "$TAILSCALE_LAN_RC"
  fi
  if [ -n "${TAILSCALE_PREFS_AFTER_LAN-}" ]; then
    printf '%s' "$TAILSCALE_PREFS_AFTER_LAN" > "$TAILSCALE_PREFS_FILE"
  fi
  exit 0
fi
if [ "$1" = set ]; then
  if [ "${TAILSCALE_SET_RC:-0}" != 0 ]; then
    printf '%s\n' "${TAILSCALE_SET_ERR-}" >&2
    exit "$TAILSCALE_SET_RC"
  fi
  if [ -n "${TAILSCALE_STATUS_AFTER-}" ]; then
    printf '%s' "$TAILSCALE_STATUS_AFTER" > "$TAILSCALE_STATUS_FILE"
  fi
  if [ -n "${TAILSCALE_PREFS_AFTER-}" ]; then
    printf '%s' "$TAILSCALE_PREFS_AFTER" > "$TAILSCALE_PREFS_FILE"
  fi
  exit 0
fi
if [ "$1" = up ]; then
  if [ "${TAILSCALE_UP_RC:-0}" != 0 ]; then
    printf '%s\n' "${TAILSCALE_UP_ERR-}" >&2
    exit "$TAILSCALE_UP_RC"
  fi
  if [ -n "${TAILSCALE_STATUS_AFTER_UP-}" ]; then
    printf '%s' "$TAILSCALE_STATUS_AFTER_UP" > "$TAILSCALE_STATUS_FILE"
  fi
  if [ -n "${TAILSCALE_PREFS_AFTER_UP-}" ]; then
    printf '%s' "$TAILSCALE_PREFS_AFTER_UP" > "$TAILSCALE_PREFS_FILE"
  fi
  exit 0
fi
exit 1
EOF
chmod +x "$bin/tailscale"

AUTH='tskey-auth-SECRETVALUE'
NODE='nodekey:SECRETVALUE'
URL='https://login.tailscale.com/a/SECRETVALUE'
HOSTN='xai-ts-connector-us-east'
DECOY_IP='100.64.0.9'

json_running_exit="{\"BackendState\":\"Running\",\"AuthKey\":\"$AUTH\",\"ExitNodeStatus\":{\"Online\":true}}"
json_running_none="{\"BackendState\":\"Running\",\"Self\":{\"NodeKey\":\"$NODE\"}}"
json_stopped="{\"BackendState\":\"Stopped\",\"AuthKey\":\"$AUTH\"}"
json_needs="{\"BackendState\":\"NeedsLogin\",\"AuthURL\":\"$URL\"}"
json_starting="{\"BackendState\":\"Starting\"}"
json_prefs_out='{"WantRunning":false,"LoggedOut":true,"ExitNodeID":"","ExitNodeIP":"","AutoExitNode":"","ExitNodeAllowLANAccess":false}'
json_prefs_none='{"WantRunning":true,"LoggedOut":false,"ExitNodeID":"","ExitNodeIP":"","AutoExitNode":"","ExitNodeAllowLANAccess":true}'
json_prefs_none_nolan='{"WantRunning":true,"LoggedOut":false,"ExitNodeID":"","ExitNodeIP":"","AutoExitNode":"","ExitNodeAllowLANAccess":false}'
json_prefs_stopped='{"WantRunning":false,"LoggedOut":false,"ExitNodeID":"","ExitNodeIP":"","AutoExitNode":"","ExitNodeAllowLANAccess":true}'
json_prefs_stopped_nolan='{"WantRunning":false,"LoggedOut":false,"ExitNodeID":"","ExitNodeIP":"","AutoExitNode":"","ExitNodeAllowLANAccess":false}'
json_prefs_id='{"WantRunning":true,"LoggedOut":false,"ExitNodeID":"nEXAMPLEID","ExitNodeIP":"","AutoExitNode":"","ExitNodeAllowLANAccess":true}'
json_prefs_auto='{"WantRunning":true,"LoggedOut":false,"ExitNodeID":"","ExitNodeIP":"","AutoExitNode":"any","ExitNodeAllowLANAccess":true}'
json_prefs_exit_nolan='{"WantRunning":true,"LoggedOut":false,"ExitNodeID":"nEXAMPLEID","ExitNodeIP":"","AutoExitNode":"","ExitNodeAllowLANAccess":false}'

export TAILSCALE_LOG="$log" TAILSCALE_STATUS_FILE="$status_file" TAILSCALE_PREFS_FILE="$prefs_file"
export PATH="$bin:$safe"

reset_cli() {
  : > "$log"
  export TAILSCALE_BIN="$bin/tailscale"
  export TAILSCALE_SET_RC=0 TAILSCALE_UP_RC=0
  export TAILSCALE_SET_ERR="" TAILSCALE_UP_ERR=""
  export TAILSCALE_SET_HELP="--exit-node value (IP, base name, or auto:any)"
  export TAILSCALE_UP_HELP="--timeout value"
  export TAILSCALE_SUGGEST=""
  export TAILSCALE_STATUS_AFTER="" TAILSCALE_PREFS_AFTER=""
  export TAILSCALE_STATUS_AFTER_UP="" TAILSCALE_PREFS_AFTER_UP=""
  export TAILSCALE_LAN_RC=0 TAILSCALE_LAN_ERR="" TAILSCALE_PREFS_AFTER_LAN=""
}
put() { # status prefs
  printf '%s' "$1" > "$status_file"
  printf '%s' "$2" > "$prefs_file"
}

# shellcheck source=../checks/login-items.sh disable=SC1091
MACCONFIG_CHECKS_DEFINE_ONLY=1
DOTDIR="$DIR"
# shellcheck disable=SC1091
. "$DIR/checks/login-items.sh"
unset MACCONFIG_CHECKS_DEFINE_ONLY

CHECKED=0
fixid_seen=""
lines=""
fixid() { fixid_seen="$1"; }
pass() { lines="${lines}ok|$1"$'\n'; }
warn() { lines="${lines}warn|$1"$'\n'; }
bad() { lines="${lines}bad|$1"$'\n'; }
info() { lines="${lines}info|$1"$'\n'; }
skip() { lines="${lines}skip|$1"$'\n'; }

run_check() {
  lines=""
  CHECKED=0
  fixid_seen=""
  check_tailscale_exit
  out="$lines"
}
run_lan() {
  lines=""
  CHECKED=0
  fixid_seen=""
  check_tailscale_lan
  out="$lines"
}
run_fix() { # 1 = dry run
  rc=0
  if [ "${1:-0}" = 1 ]; then
    out="$(DRY_RUN=1 safe_tailscale_exit 2>&1)" || rc=$?
  else
    out="$(DRY_RUN=0 safe_tailscale_exit 2>&1)" || rc=$?
  fi
}

# ---- list and wiring -------------------------------------------------------
eq "tailscale-exit is SAFE" "SAFE|tailscale" \
  "$(awk -F'|' '$1=="tailscale-exit" { print $2 "|" $3; exit }' "$DIR/lib/autofix.list")"
has "the login-items file calls the exit check" "check_tailscale_exit" "$(cat "$DIR/checks/login-items.sh")"
has "Tailscale is its own heading" 'hdr "Tailscale"' "$(cat "$DIR/checks/login-items.sh")"
eq "safe path hides tailscale" "" "$(PATH="$safe" command -v tailscale || true)"
eq "helper never runs sudo" "" "$(grep -nE '(^|[[:space:]])sudo([[:space:]]|$)' "$DIR/lib/safe-fixers.sh" || true)"
eq "helper does not call syspolicy" "" "$(grep -n syspolicy "$DIR/lib/safe-fixers.sh" || true)"
has "the real install runs the Tailscale helper" "safe_tailscale_exit" \
  "$(awk '/uname -s/,0' "$DIR/install.sh")"
has "a Tailscale miss does not abort setup" 'safe_tailscale_exit || ts_rc=$?' "$(cat "$DIR/install.sh")"

# ---- probe and check -------------------------------------------------------
reset_cli
put "$json_running_exit" "$json_prefs_none"
eq "status exit node probes as running-exit" running-exit "$(tailscale_exit_probe "$bin/tailscale")"
has "the CLI is forced into CLI mode" "BE=1" "$(cat "$log")"
run_check
eq "any selected exit node passes" ok "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "the pass line does not name the node" "an exit node selected" "$out"
eq "the pass is tagged tailscale-exit" tailscale-exit "$fixid_seen"
eq "the pass is counted" 1 "$CHECKED"
miss "a pass is not drift" "bad|" "$out"
miss "a pass does not print the auth key" "$AUTH" "$out"
run_fix
eq "an already selected node is left alone" 0 "$rc"
has "already selected is reported" "already running with an exit node selected" "$out"
miss "an already selected node is not changed" "set --exit-node" "$(cat "$log")"
miss "an already selected node does not print the auth key" "$AUTH" "$out"

reset_cli
put "$json_running_none" "$json_prefs_id"
eq "prefs ExitNodeID counts as selected" running-exit "$(tailscale_exit_probe "$bin/tailscale")"
run_check
eq "a prefs exit node passes" ok "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
miss "a prefs exit node does not print the id" "nEXAMPLEID" "$out"

reset_cli
put "$json_running_none" "$json_prefs_auto"
eq "AutoExitNode counts as selected" running-exit "$(tailscale_exit_probe "$bin/tailscale")"
run_check
eq "auto exit node passes" ok "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"

reset_cli
put "$json_running_none" "$json_prefs_none"
eq "running with no exit node probes as running-none" running-none "$(tailscale_exit_probe "$bin/tailscale")"
run_check
eq "no exit node is a warning" warn "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "no exit node says any selected node counts" "any selected exit node counts" "$out"
miss "no exit node is not drift" "bad|" "$out"
miss "no exit node does not print the node key" "$NODE" "$out"
run_lan
eq "Allow Local Network Access on with no exit node passes" ok "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "Allow Local Network Access on is the pass" "Allow Local Network Access is on" "$out"
eq "Allow Local Network Access on is tagged tailscale-exit" tailscale-exit "$fixid_seen"
miss "Allow Local Network Access on is not drift" "bad|" "$out"

reset_cli
put "$json_running_none" "$json_prefs_none_nolan"
eq "no exit node with Allow Local Network Access off is still running-none" running-none "$(tailscale_exit_probe "$bin/tailscale")"
eq "Allow Local Network Access off probes as no" no "$(tailscale_lan_probe "$bin/tailscale")"
run_lan
eq "no exit node does not warn about Allow Local Network Access" "" "$out"
eq "no exit node does not count the Allow Local Network Access check" 0 "$CHECKED"

reset_cli
put "$json_running_exit" "$json_prefs_none"
run_lan
eq "Allow Local Network Access on with an exit node passes" ok "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
eq "that pass is counted" 1 "$CHECKED"
miss "that pass does not print the auth key" "$AUTH" "$out"

reset_cli
put "$json_running_exit" "$json_prefs_exit_nolan"
run_check
eq "an exit node still passes when Allow Local Network Access is off" ok "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
run_lan
eq "an exit node with Allow Local Network Access off is a warning" warn "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "the warning names Allow Local Network Access" "Allow Local Network Access off" "$out"
has "the warning names the setter" "--exit-node-allow-lan-access=true" "$out"
eq "the warning is tagged tailscale-exit" tailscale-exit "$fixid_seen"
eq "the warning is counted" 1 "$CHECKED"
miss "Allow Local Network Access off is not drift" "bad|" "$out"
miss "the warning does not print the exit node id" "nEXAMPLEID" "$out"

reset_cli
put "$json_stopped" "$json_prefs_stopped_nolan"
run_lan
eq "stopped does not warn about Allow Local Network Access" "" "$out"

reset_cli
put "$json_needs" "$json_prefs_out"
run_lan
eq "signed out does not warn about Allow Local Network Access" "" "$out"

reset_cli
export TAILSCALE_BIN="$tmp/no-such-tailscale"
run_lan
eq "a missing CLI does not add an Allow Local Network Access line" "" "$out"

reset_cli
put "$json_running_exit" "not-json"
run_lan
eq "unreadable Allow Local Network Access is a warning" warn "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "unreadable Allow Local Network Access does not fail the run" "does not fail the run" "$out"
miss "unreadable Allow Local Network Access is not drift" "bad|" "$out"
miss "unreadable Allow Local Network Access does not echo the body" "not-json" "$out"

reset_cli
put "$json_needs" "$json_prefs_out"
eq "needs login probes as logged-out" logged-out "$(tailscale_exit_probe "$bin/tailscale")"
run_check
eq "signed out is a warning" warn "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "signed out names the manual step" "tailscale-signin" "$out"
miss "signed out is not drift" "bad|" "$out"
miss "signed out does not print the auth URL" "$URL" "$out"
run_fix
eq "signed out is not changed" 2 "$rc"
has "signed out names the manual step from the fixer" "tailscale-signin" "$out"
miss "signed out does not run up" $'\nup' "$(printf '\n%s\n' "$(cat "$log")")"
miss "signed out does not set an exit node" "set --exit-node" "$(cat "$log")"
miss "signed out fixer does not print the auth URL" "$URL" "$out"

reset_cli
put "$json_stopped" "$json_prefs_out"
eq "stopped and logged out probes as logged-out" logged-out "$(tailscale_exit_probe "$bin/tailscale")"

reset_cli
put "$json_stopped" "$json_prefs_stopped"
eq "stopped and signed in probes as stopped" stopped "$(tailscale_exit_probe "$bin/tailscale")"
run_check
eq "stopped is a warning" warn "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "stopped says fix turns it on" "turns it on" "$out"
miss "stopped is not drift" "bad|" "$out"

reset_cli
put "$json_starting" "$json_prefs_none"
eq "starting probes as starting" starting "$(tailscale_exit_probe "$bin/tailscale")"
run_check
eq "starting is a warning" warn "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
run_fix
eq "starting is not changed" 2 "$rc"
miss "starting does not run up" $'\nup' "$(printf '\n%s\n' "$(cat "$log")")"

reset_cli
printf '%s' 'not-json' > "$status_file"
printf '%s' "$json_prefs_none" > "$prefs_file"
eq "bad status probes as unreadable" unreadable "$(tailscale_exit_probe "$bin/tailscale")"
run_check
eq "unreadable status is a warning" warn "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "unreadable status says the run does not fail" "does not fail the run" "$out"
miss "unreadable status does not echo the body" "not-json" "$out"
run_fix
eq "unreadable status is not changed" 2 "$rc"
miss "unreadable status does not set an exit node" "set --exit-node" "$(cat "$log")"

reset_cli
export TAILSCALE_BIN="$tmp/no-such-tailscale"
run_check
eq "a missing CLI is a warning" warn "$(printf '%s\n' "$out" | head -n 1 | cut -d'|' -f1)"
has "a missing CLI names Fleet" "Fleet Self service" "$out"
miss "a missing CLI is not drift" "bad|" "$out"
eq "a missing CLI is still counted" 1 "$CHECKED"
run_fix
eq "a missing CLI is not changed" 2 "$rc"
has "a missing CLI says it is not installed" "not installed" "$out"
eq "a missing CLI does not run" "" "$(cat "$log")"
run_fix 1
eq "dry-run with no CLI exits 2" 2 "$rc"
has "dry-run with no CLI would leave it" "would leave Tailscale alone" "$out"

# ---- fixer applies ---------------------------------------------------------
reset_cli
put "$json_running_none" "$json_prefs_none"
export TAILSCALE_STATUS_AFTER="$json_running_exit"
export TAILSCALE_SUGGEST="SECRETNODE"
run_fix
eq "auto:any set exits 0" 0 "$rc"
has "auto:any set reports running" "Tailscale is running with an exit node selected" "$out"
has "auto:any is what was set" "set --exit-node=auto:any" "$(cat "$log")"
miss "auto:any does not ask suggest" "exit-node suggest" "$(cat "$log")"
miss "auto:any does not print the suggest trap" "SECRETNODE" "$out"
miss "auto:any does not run up when already running" $'\nup' "$(printf '\n%s\n' "$(cat "$log")")"
miss "auto:any does not print the node key" "$NODE" "$out"
has "set stays in CLI mode" "BE=1" "$(cat "$log")"

reset_cli
put "$json_running_none" "$json_prefs_none"
export TAILSCALE_SET_HELP="--exit-node value (IP or base name)"
export TAILSCALE_SUGGEST="Suggested exit node: ${HOSTN}.
To accept this suggestion, use \`tailscale set --exit-node=${DECOY_IP}\`."
export TAILSCALE_STATUS_AFTER="$json_running_exit"
run_fix
eq "suggest hostname set exits 0" 0 "$rc"
has "suggest uses the hostname, not the example address" "set --exit-node=${HOSTN}" "$(cat "$log")"
miss "suggest does not pass the example address" "set --exit-node=${DECOY_IP}" "$(cat "$log")"
miss "suggest does not print the hostname" "$HOSTN" "$out"
miss "suggest does not print the example address" "$DECOY_IP" "$out"

reset_cli
put "$json_running_none" "$json_prefs_none"
export TAILSCALE_SET_RC=1
export TAILSCALE_SET_ERR="$URL policy blocked"
run_fix
eq "a refused set exits 2" 2 "$rc"
has "a refused set names managed policy" "Managed policy may block the change" "$out"
has "a refused set says any selected node counts" "Any exit node already selected still counts" "$out"
miss "a refused set does not print the auth URL" "SECRETVALUE" "$out"
miss "a refused set does not claim it is running" "already running" "$out"

reset_cli
put "$json_running_none" "$json_prefs_none"
export TAILSCALE_STATUS_AFTER="$json_running_none"
run_fix
eq "a set that does not stick exits 2" 2 "$rc"
has "a set that does not stick says so" "did not stick" "$out"

reset_cli
put "$json_stopped" "$json_prefs_stopped"
export TAILSCALE_STATUS_AFTER_UP="$json_running_exit"
run_fix
eq "up onto an existing exit node exits 0" 0 "$rc"
has "up uses the timeout flag" "up --timeout=15s" "$(cat "$log")"
miss "up onto an existing exit node does not set another" "set --exit-node" "$(cat "$log")"
has "up onto an existing exit node reports running" "running with an exit node selected" "$out"
miss "up does not print the auth key" "$AUTH" "$out"

reset_cli
put "$json_stopped" "$json_prefs_stopped"
export TAILSCALE_STATUS_AFTER_UP="$json_running_none"
export TAILSCALE_STATUS_AFTER="$json_running_exit"
run_fix
eq "up then set exits 0" 0 "$rc"
has "up then set runs up" "up --timeout=15s" "$(cat "$log")"
has "up then set selects auto:any" "set --exit-node=auto:any" "$(cat "$log")"

reset_cli
put "$json_stopped" "$json_prefs_stopped"
export TAILSCALE_UP_RC=1
export TAILSCALE_UP_ERR="$URL"
run_fix
eq "up that fails exits 2" 2 "$rc"
has "up that fails says it may be offline" "may be offline" "$out"
miss "up that fails does not set an exit node" "set --exit-node" "$(cat "$log")"
miss "up that fails does not print the auth URL" "SECRETVALUE" "$out"

reset_cli
put "$json_stopped" "$json_prefs_stopped"
run_fix 1
eq "dry-run of a stopped CLI exits 0" 0 "$rc"
has "dry-run names up and set" "would turn Tailscale on" "$out"
miss "dry-run does not run up" "up --timeout" "$(cat "$log")"
miss "dry-run does not set an exit node" "set --exit-node" "$(cat "$log")"

reset_cli
export TAILSCALE_SET_HELP="--exit-node value"
export TAILSCALE_SUGGEST="No suggestion available."
put "$json_running_none" "$json_prefs_none"
run_fix
eq "no suggestion exits 2" 2 "$rc"
has "no suggestion says so" "no recommended exit node" "$out"
miss "no suggestion does not set an exit node" "set --exit-node" "$(cat "$log")"
miss "no suggestion does not turn on Allow Local Network Access" "--exit-node-allow-lan-access" "$(cat "$log")"

reset_cli
put "$json_running_exit" "$json_prefs_exit_nolan"
export TAILSCALE_PREFS_AFTER_LAN="$json_prefs_id"
run_fix
eq "Allow Local Network Access set exits 0" 0 "$rc"
has "Allow Local Network Access set reports it is on" "Allow Local Network Access is on" "$out"
has "Allow Local Network Access is what was set" "set --exit-node-allow-lan-access=true" "$(cat "$log")"
miss "an already selected node is not replaced to turn on local access" "set --exit-node=" "$(cat "$log")"
miss "Allow Local Network Access set does not print the exit node id" "nEXAMPLEID" "$out"
has "Allow Local Network Access set stays in CLI mode" "BE=1" "$(cat "$log")"

reset_cli
put "$json_running_exit" "$json_prefs_exit_nolan"
export TAILSCALE_LAN_RC=1
export TAILSCALE_LAN_ERR="$URL policy blocked"
run_fix
eq "a refused Allow Local Network Access set exits 2" 2 "$rc"
has "a refused Allow Local Network Access set names managed policy" "Managed policy may block the change" "$out"
miss "a refused Allow Local Network Access set does not print the auth URL" "SECRETVALUE" "$out"
miss "a refused Allow Local Network Access set does not claim it is on" "Allow Local Network Access is on" "$out"

reset_cli
put "$json_running_exit" "$json_prefs_exit_nolan"
run_fix
eq "Allow Local Network Access that does not stick exits 2" 2 "$rc"
has "Allow Local Network Access that does not stick says so" "did not stick" "$out"

reset_cli
put "$json_running_exit" "$json_prefs_exit_nolan"
run_fix 1
eq "dry-run of Allow Local Network Access exits 0" 0 "$rc"
has "dry-run names Allow Local Network Access" "would turn on Allow Local Network Access" "$out"
miss "dry-run does not turn on Allow Local Network Access" "--exit-node-allow-lan-access=true" "$(cat "$log")"

reset_cli
put "$json_running_none" "$json_prefs_none_nolan"
export TAILSCALE_STATUS_AFTER="$json_running_exit"
export TAILSCALE_PREFS_AFTER_LAN="$json_prefs_id"
run_fix
eq "exit node then Allow Local Network Access exits 0" 0 "$rc"
has "exit node then Allow Local Network Access selects auto:any" "set --exit-node=auto:any" "$(cat "$log")"
has "exit node then Allow Local Network Access sets the pref" "set --exit-node-allow-lan-access=true" "$(cat "$log")"
miss "exit node then Allow Local Network Access does not print the node key" "$NODE" "$out"

reset_cli
put "$json_stopped" "$json_prefs_stopped_nolan"
export TAILSCALE_STATUS_AFTER_UP="$json_running_exit"
export TAILSCALE_PREFS_AFTER_LAN="$json_prefs_id"
run_fix
eq "up then Allow Local Network Access exits 0" 0 "$rc"
has "up then Allow Local Network Access runs up" "up --timeout=15s" "$(cat "$log")"
has "up then Allow Local Network Access sets the pref" "set --exit-node-allow-lan-access=true" "$(cat "$log")"
miss "up then Allow Local Network Access does not select another node" "set --exit-node=" "$(cat "$log")"

# ---- the section, and install.sh --dry-run ---------------------------------
section="$(
  set -euo pipefail
  unset MACCONFIG_CHECKS_DEFINE_ONLY
  export DOTDIR="$DIR" PATH="$bin:$safe" TAILSCALE_BIN="$bin/tailscale"
  export TAILSCALE_APP_PATH="$tmp/no-such-app"
  export TAILSCALE_LOG="$log" TAILSCALE_STATUS_FILE="$status_file" TAILSCALE_PREFS_FILE="$prefs_file"
  export TAILSCALE_SET_RC=0 TAILSCALE_UP_RC=0
  CHECKED=0
  hdr() { printf '[%s]\n' "$1"; }
  fixid() { printf 'fixid %s\n' "$1"; }
  pass() { printf 'ok %s\n' "$1"; }
  warn() { printf 'warn %s\n' "$1"; }
  bad() { printf 'DRIFT %s\n' "$1"; }
  info() { printf 'info %s\n' "$1"; }
  skip() { printf 'skip %s\n' "$1"; }
  printf '%s' "$json_running_exit" > "$status_file"
  printf '%s' "$json_prefs_none" > "$prefs_file"
  # shellcheck source=../checks/login-items.sh disable=SC1091
  . "$DIR/checks/login-items.sh"
)"
has "the section keeps Login Items" "[Login Items]" "$section"
has "the section has a Tailscale heading" "[Tailscale]" "$section"
has "a missing app skips Open at Login" "skip Tailscale is not installed yet" "$section"
has "the section passes a selected exit node" "ok Tailscale is running with an exit node selected" "$section"
has "the section passes Allow Local Network Access" "ok Tailscale Allow Local Network Access is on" "$section"
miss "the section does not drift" "DRIFT" "$section"
has "the section tags the exit check" "fixid tailscale-exit" "$section"

dry_home="$tmp/dry-home"
mkdir -p "$dry_home"
: > "$log"
dry_rc=0
dry_out="$(HOME="$dry_home" PATH="$bin:$safe" TAILSCALE_BIN="$tmp/no-such-tailscale" \
  TAILSCALE_LOG="$log" "$DIR/install.sh" --dry-run 2>&1)" || dry_rc=$?
eq "install.sh --dry-run with no CLI exits 0" 0 "$dry_rc"
has "install.sh --dry-run with no CLI leaves Tailscale" "would leave Tailscale alone" "$dry_out"
has "install.sh --dry-run says nothing is changed" "nothing is changed" "$dry_out"
eq "install.sh --dry-run with no CLI does not run it" "" "$(cat "$log")"

reset_cli
put "$json_stopped" "$json_prefs_stopped"
: > "$log"
dry_rc=0
dry_out="$(HOME="$dry_home" PATH="$bin:$safe" \
  TAILSCALE_BIN="$bin/tailscale" TAILSCALE_LOG="$log" \
  TAILSCALE_STATUS_FILE="$status_file" TAILSCALE_PREFS_FILE="$prefs_file" \
  TAILSCALE_SET_HELP="--exit-node value (IP, base name, or auto:any)" \
  TAILSCALE_UP_HELP="--timeout value" \
  "$DIR/install.sh" --dry-run 2>&1)" || dry_rc=$?
eq "install.sh --dry-run with a stopped CLI exits 0" 0 "$dry_rc"
has "install.sh --dry-run describes the Tailscale step" "would turn Tailscale on" "$dry_out"
miss "install.sh --dry-run does not run up" "up --timeout" "$(cat "$log")"
miss "install.sh --dry-run does not set an exit node" "set --exit-node" "$(cat "$log")"

printf 'tailscale-exit tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
