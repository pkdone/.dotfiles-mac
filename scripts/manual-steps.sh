#!/usr/bin/env bash
#
# manual-steps.sh — the steps no script can do (privacy permissions, sign-ins, MDM
# apps, settings not exposed via `defaults`), read from lib/manual-steps.list.
#
#   list [--markdown]   numbered checklist (or a Markdown table for docs/manual-steps.md)
#   open [--all]        interactive walk-through: opens each step's settings page and
#                       waits for Enter. Skips steps whose check already passes unless
#                       --all. Under each title, one line says why the step is shown.
#                       Prints a group heading only for a group that still has a
#                       step to show. Does nothing when stdin isn't a terminal.
#                       A check of @macconfig:<area> runs that section's step function
#                       once (lib/covered-steps.sh). It does not run the whole of macconfig.
#   check [--porcelain] run each step's read-only check: ok / warn / check by hand.
#                       Human output groups lines under the same headings as list.
#                       --porcelain prints status|num|id|title|detail for macconfig-check.sh
#                       (no headings). Exit status: 1 if any automated check warns, else 0.
#   validate            parse the list and report malformed rows (used by tests/).
#
# Read-only: never writes a setting, and every slow call is wrapped in a timeout so a
# check can't hang or prompt. Bash 3.2-safe (stock macOS bash).
#
set -uo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="${MANUAL_STEPS_LIST:-$DOTDIR/lib/manual-steps.list}"
TCC_DB="${MANUAL_STEPS_TCC_DB:-/Library/Application Support/com.apple.TCC/TCC.db}"
NAMED_CHECKS=" hammerspoon-ax karabiner-driver pointer-size input-british op-cli gh-auth spotlight-results remove-widgets home-printer tailscale-signin edge-light whatsapp-web "

usage() {
  cat <<'USAGE'
Usage: scripts/manual-steps.sh <command> [option]
  list [--markdown]    Print the manual steps as a numbered checklist (or Markdown table).
  pending              Print only steps that are not set or can't be checked, with
                       the same why-shown line as open. Says how many were already done.
  open [--all]         Walk through the steps one by one, opening each settings page.
                       Skips steps already verified ok unless --all. Needs a terminal.
  check [--porcelain]  Run the read-only checks: ok, warn or check by hand.
  validate             Check lib/manual-steps.list for malformed rows.
  -h, --help           Show this help.
Steps live in lib/manual-steps.list (MANUAL_STEPS_LIST overrides the path).
USAGE
}

# ---- colour (only on a terminal) ----------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR+x}" ]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_DIM=$'\033[2m'; C_HDR=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_OK=''; C_WARN=''; C_DIM=''; C_HDR=''; C_OFF=''
fi

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

# with_timeout SECS CMD... — macOS has no timeout(1) by default; perl's alarm survives
# exec, so CMD is killed (SIGALRM, status 142) if it runs longer than SECS.
with_timeout() {
  local secs="$1"; shift
  perl -e '$t = shift @ARGV; alarm $t; exec { $ARGV[0] } @ARGV or exit 127' "$secs" "$@"
}

# ---- parse the list into parallel arrays --------------------------------
S_ID=(); S_GROUP=(); S_TITLE=(); S_WHERE=(); S_OPEN=(); S_CHECK=(); ERRORS=()
N=0
load_steps() {
  [ -r "$LIST" ] || { echo "Error: steps list not found: $LIST" >&2; exit 2; }
  local line lineno=0 id group title where target chk extra seen=" " groups_done=" " last_group=""
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    case "$(trim "$line")" in ''|'#'*) continue ;; esac
    IFS='|' read -r id group title where target chk extra <<< "$line"
    id="$(trim "$id")"; group="$(trim "$group")"; title="$(trim "$title")"
    where="$(trim "$where")"; target="$(trim "$target")"; chk="$(trim "$chk")"
    if [ -n "$extra" ]; then ERRORS+=("line $lineno: too many fields (expected 6)"); continue; fi
    if [ -z "$id" ] || [ -z "$group" ] || [ -z "$title" ] || [ -z "$where" ]; then
      ERRORS+=("line $lineno: id, group, title and where are required"); continue
    fi
    case "$id" in *[!a-z0-9-]*) ERRORS+=("line $lineno: id '$id' must be kebab-case [a-z0-9-]") ;; esac
    case "$seen" in *" $id "*) ERRORS+=("line $lineno: duplicate id '$id'") ;; esac
    seen="$seen$id "
    if [ "$group" != "$last_group" ]; then
      case "$groups_done" in *"|$group|"*) ERRORS+=("line $lineno: group '$group' is split; keep its steps together") ;; esac
      groups_done="$groups_done|$group|"; last_group="$group"
    fi
    case "$target" in
      ''|x-apple.systempreferences:?*|https://?*|macappstore://*|app:?*|safari:https://?*) ;;
      *) ERRORS+=("line $lineno: open '$target' must be x-apple.systempreferences:, https://, safari:https://, macappstore:// or app:") ;;
    esac
    check_spec_ok "$chk" || ERRORS+=("line $lineno: unknown check '$chk'")
    S_ID+=("$id"); S_GROUP+=("$group"); S_TITLE+=("$title"); S_WHERE+=("$where")
    S_OPEN+=("$target"); S_CHECK+=("$chk")
    N=$((N + 1))
  done < "$LIST"
}

# Validate a check spec's syntax (values end up in a SQL string / defaults call, so
# keep them to safe characters).
check_spec_ok() {
  local spec="$1" rest
  case "$spec" in
    ''|'@macconfig-check.sh') return 0 ;;
    @macconfig:*)
      rest="${spec#@macconfig:}"
      case "$rest" in
        mdm|karabiner|display|power|notifications|login-items|finder|modes) return 0 ;;
      esac
      return 1
      ;;
    tcc:*)
      rest="${spec#tcc:}"
      case "$rest" in *:*) ;; *) return 1 ;; esac
      case "${rest%%:*}${rest#*:}" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
      return 0 ;;
    defaults:*)
      rest="${spec#defaults:}"
      case "$rest" in ?*:?*=*) ;; *) return 1 ;; esac
      case "$rest" in *[!A-Za-z0-9._:=,@/-]*) return 1 ;; esac
      return 0 ;;
    app:?*) return 0 ;;
    logi:?*)
      case "${spec#logi:}" in *[!a-z0-9,-]*|,*|*,|*,,*) return 1 ;; esac
      return 0 ;;
  esac
  case "$NAMED_CHECKS" in *" $spec "*) return 0 ;; esac
  return 1
}

# ---- checks: each sets R_STATUS (ok|warn|hand|covered) and R_DETAIL -------
R_STATUS=""; R_DETAIL=""
res() { R_STATUS="$1"; R_DETAIL="$2"; }

# British input, pointer size, gh auth, 1Password CLI, and Spotlight.
# macconfig-check.sh prints this script's result and does not run these again.
# shellcheck source=../lib/session-checks.sh disable=SC1091
. "$DOTDIR/lib/session-checks.sh"
# shellcheck source=../lib/fleet-apps.sh disable=SC1091
. "$DOTDIR/lib/fleet-apps.sh"
# shellcheck source=../lib/covered-steps.sh disable=SC1091
. "$DOTDIR/lib/covered-steps.sh"

# Allowed in the system TCC database? Reading it needs Full Disk Access for whatever
# runs this (Ghostty / Grok Bot); without it, fall back to check by hand.
check_tcc() {  # service bundle-id
  local svc="$1" bundle="$2" out rc
  if ! command -v sqlite3 >/dev/null 2>&1; then res hand "sqlite3 not found"; return; fi
  out="$(with_timeout 5 sqlite3 -readonly "$TCC_DB" \
    "SELECT auth_value FROM access WHERE service='kTCCService$svc' AND client='$bundle' AND client_type=0 LIMIT 1;" 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    res hand "can't read the privacy database here (needs Full Disk Access)"; return
  fi
  case "$out" in
    2|3) res ok "allowed" ;;
    0)   res warn "listed but switched off" ;;
    '')  res warn "not in the list yet" ;;
    *)   res hand "unexpected TCC value '$out'" ;;
  esac
}

# Exact text first. A float may print as 1.5 or 1.500000; both satisfy a numeric want.
defaults_value_match() {  # actual want
  [ "$1" = "$2" ] && return 0
  case "$1" in ''|*[!0-9.+-]*) return 1 ;; esac
  case "$2" in ''|*[!0-9.+-]*) return 1 ;; esac
  awk -v a="$1" -v w="$2" 'BEGIN { exit !(a+0 == w+0) }'
}

check_defaults() {  # domain k=v[,k=v]
  local domain="$1" pairs="$2" pair key want cur bad="" ok="" unchecked=""
  if ! defaults read "$domain" >/dev/null 2>&1; then
    res hand "can't read $domain"; return
  fi
  local IFS=','
  for pair in $pairs; do
    key="${pair%%=*}"; want="${pair#*=}"
    if cur="$(defaults read "$domain" "$key" 2>/dev/null)"; then
      if defaults_value_match "$cur" "$want"; then ok="$ok $key=$cur"; else bad="$bad $key=$cur (want $want)"; fi
    elif [ "$domain" = com.raycast.macos ] && [ "$key" = raycastGlobalHotkey ]; then
      # Current Raycast does not store this key, even when the hotkey is set.
      unchecked="$unchecked $key is not stored, so this can't be checked"
    else
      bad="$bad $key not set (want $want)"
    fi
  done
  if [ -n "$bad" ]; then res warn "${bad# }"; elif [ -n "$unchecked" ]; then res hand "${unchecked# }"; else res ok "${ok# }"; fi
}

check_hammerspoon_ax() {
  if [ ! -d /Applications/Hammerspoon.app ]; then res warn "Hammerspoon.app not installed (brew bundle)"; return; fi
  if pgrep -xq Hammerspoon && command -v hs >/dev/null 2>&1; then
    # -q: result only; -t: IPC timeout. </dev/null matters: hs reads stdin when it's a
    # pipe (launchd/agent runs) and would otherwise wait forever.
    case "$(with_timeout 6 hs -q -t 3 -c 'hs.accessibilityState()' </dev/null 2>/dev/null)" in
      true)  res ok "granted (live, via hs)"; return ;;
      false) res warn "not granted — open Hammerspoon first, then System Settings → Privacy & Security → Accessibility. If it is not listed, click + and add it from Applications, then restart Hammerspoon"; return ;;
    esac
  fi
  # Not running, or hs.ipc unavailable: fall back to the TCC database.
  check_tcc Accessibility org.hammerspoon.Hammerspoon
}

check_karabiner_driver() {
  local se
  if ! command -v systemextensionsctl >/dev/null 2>&1; then res hand "systemextensionsctl unavailable"; return; fi
  se="$(with_timeout 10 systemextensionsctl list 2>/dev/null)"
  if printf '%s\n' "$se" | grep -Eq 'org\.pqrs\.Karabiner-DriverKit-VirtualHIDDevice.*\[activated enabled\]'; then
    res ok "activated and enabled"
  else
    res warn "not activated and enabled"
  fi
}

# tailscale-signin — read `status --json` only. Never log in, and never
# print an auth key or a node key. The app binary is preferred; `tailscale`
# on PATH is the fallback. MANUAL_STEPS_TAILSCALE_BIN overrides that path
# in tests. TAILSCALE_BE_CLI=1 keeps the app binary in CLI mode so a
# non-terminal run does not open the Tailscale window.
# ok only when BackendState is Running and the logged-in LoginName is
# paul.done@anysphere.co.
check_tailscale_signin() {
  local bin="" json="" parsed="" state="" login="" py=""
  if [ -n "${MANUAL_STEPS_TAILSCALE_BIN+x}" ]; then
    bin="$MANUAL_STEPS_TAILSCALE_BIN"
  elif [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]; then
    bin=/Applications/Tailscale.app/Contents/MacOS/Tailscale
  elif command -v tailscale >/dev/null 2>&1; then
    bin="$(command -v tailscale)"
  else
    bin=""
  fi
  if [ -z "$bin" ] || [ ! -x "$bin" ]; then
    res hand "Tailscale CLI can't be run"
    return
  fi
  py="$(command -v python3 2>/dev/null || true)"
  if [ -z "$py" ]; then
    res hand "Tailscale CLI can't be run"
    return
  fi
  json="$(TAILSCALE_BE_CLI=1 with_timeout 15 "$bin" status --json 2>/dev/null || true)"
  if [ -z "$json" ]; then
    res hand "Tailscale CLI can't be run"
    return
  fi
  parsed="$(printf '%s' "$json" | "$py" -c '
import json, sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except Exception:
    print("bad|")
    raise SystemExit(0)
if not isinstance(data, dict):
    print("bad|")
    raise SystemExit(0)
state = data.get("BackendState")
state = state if isinstance(state, str) else ""
login = ""
users = data.get("User")
self_node = data.get("Self")
uid = self_node.get("UserID") if isinstance(self_node, dict) else None
if isinstance(users, dict) and uid is not None:
    user = users.get(str(uid))
    if isinstance(user, dict):
        name = user.get("LoginName")
        if isinstance(name, str):
            login = name
print(state.replace("|", "/") + "|" + login.replace("|", "/"))
' 2>/dev/null || true)"
  state="${parsed%%|*}"
  login="${parsed#*|}"
  if [ -z "$parsed" ] || [ "$state" = bad ]; then
    res hand "Tailscale CLI can't be run"
    return
  fi
  if [ "$state" = Running ] && [ "$login" = "paul.done@anysphere.co" ]; then
    res ok "Tailscale is running as paul.done@anysphere.co"
    return
  fi
  if [ -n "$login" ] && [ "$login" != "paul.done@anysphere.co" ]; then
    res warn "signed in as $login, want paul.done@anysphere.co"
    return
  fi
  res warn "Tailscale is ${state:-not running}"
}

# home-printer — read lpstat only. Never add a queue.
# ok when a queue name contains HP_ENVY_6000 or "HP ENVY 6000".
# Otherwise warn: it can only be added on the home network.
check_home_printer() {
  local out=""
  if ! command -v lpstat >/dev/null 2>&1; then
    res warn "HP ENVY 6000 series is not in the printer list. It can only be added on the home network"
    return
  fi
  out="$(with_timeout 10 lpstat -p 2>/dev/null || true)"
  if ! printf '%s\n' "$out" | grep -Eq 'HP_ENVY_6000|HP ENVY 6000'; then
    out="$(with_timeout 10 lpstat -v 2>/dev/null || true)"
  fi
  if printf '%s\n' "$out" | grep -Eq 'HP_ENVY_6000|HP ENVY 6000'; then
    res ok "HP ENVY 6000 series is in the printer list"
    return
  fi
  res warn "HP ENVY 6000 series is not in the printer list. It can only be added on the home network"
}

# edge-light — lib/edge-light.py only tries to read. The on/off state on this
# Mac is in the protected Control Centre video-effects plist (permission
# denied). RingLightHelper's group holds no preferences. Nothing is written.
# The result is always check by hand, so open and pending always show the step.
check_edge_light() {
  local py="" p line status detail
  for p in "$(command -v python3 2>/dev/null)" /opt/homebrew/bin/python3 /usr/bin/python3; do
    if [ -n "$p" ] && [ -x "$p" ]; then py="$p"; break; fi
  done
  if [ -z "$py" ] || [ ! -r "$DOTDIR/lib/edge-light.py" ]; then
    res hand "can't be checked, so always shown"
    return
  fi
  line="$(with_timeout 15 "$py" "$DOTDIR/lib/edge-light.py" </dev/null 2>/dev/null || true)"
  status="${line%%|*}"
  detail="${line#*|}"
  if [ -z "$detail" ] || [ "$detail" = "$line" ]; then
    detail="can't be checked, so always shown"
  fi
  case "$status" in
    hand) res hand "$detail" ;;
    *) res hand "can't be checked, so always shown" ;;
  esac
}

# remove-widgets — lib/desktop-widgets.py reads widgets.instances in the
# notificationcenterui plist. It does not write that file and does not kill
# NotificationCenter or chronod. ok when no widget is placed, so `open` skips
# the step; warn when any are placed; hand when the plist cannot be read.
check_remove_widgets() {
  local py="" p line status detail
  for p in "$(command -v python3 2>/dev/null)" /opt/homebrew/bin/python3 /usr/bin/python3; do
    if [ -n "$p" ] && [ -x "$p" ]; then py="$p"; break; fi
  done
  if [ -z "$py" ]; then res hand "no python3 — can't read the desktop widget list"; return; fi
  if [ ! -r "$DOTDIR/lib/desktop-widgets.py" ]; then
    res hand "lib/desktop-widgets.py missing"
    return
  fi
  line="$(with_timeout 15 "$py" "$DOTDIR/lib/desktop-widgets.py" </dev/null 2>/dev/null || true)"
  status="${line%%|*}"
  detail="${line#*|}"
  detail="${detail#*|}"
  case "$status" in
    ok|warn|hand) res "$status" "$detail" ;;
    *) res hand "can't read the desktop widget list" ;;
  esac
}

# whatsapp-web — the Safari web app exists and its bundle id starts with
# com.apple.Safari.WebApp. The UUID is generated per Mac, so it is read from
# Contents/Info.plist and not stored. Linking the phone cannot be read.
check_whatsapp_web() {
  local app="${HOME}/Applications/WhatsApp Web.app" plist bid py rc low
  if [ ! -e "$app" ]; then
    # Quote HOME so a "." in the temp path stays literal, and keep the tilde
    # out of the replacement (bash would expand it back to $HOME).
    res warn "not found at ~${app#"$HOME"}"
    return
  fi
  plist="$app/Contents/Info.plist"
  if [ ! -f "$plist" ]; then
    res hand "can't read the bundle id"
    return
  fi
  py="$(command -v python3 2>/dev/null || true)"
  bid=""
  rc=1
  if [ -n "$py" ]; then
    bid="$(with_timeout 5 "$py" -c '
import plistlib, sys
try:
    info = plistlib.load(open(sys.argv[1], "rb"))
except Exception:
    raise SystemExit(2)
bundle = info.get("CFBundleIdentifier") if isinstance(info, dict) else None
if not isinstance(bundle, str) or not bundle.strip():
    raise SystemExit(3)
sys.stdout.write(bundle.strip())
' "$plist" 2>/dev/null)"
    rc=$?
  elif command -v defaults >/dev/null 2>&1; then
    bid="$(defaults read "${app}/Contents/Info" CFBundleIdentifier 2>/dev/null || true)"
    if [ -n "$bid" ]; then rc=0; fi
  fi
  if [ "$rc" -ne 0 ] || [ -z "$bid" ]; then
    res hand "can't read the bundle id"
    return
  fi
  low="$(printf '%s' "$bid" | tr '[:upper:]' '[:lower:]')"
  case "$low" in
    com.apple.safari.webapp.*)
      res ok "Safari web app. Linking the phone can't be checked."
      ;;
    *)
      res warn "bundle id $bid does not start with com.apple.Safari.WebApp."
      ;;
  esac
}

# logi:<id>[,<id>] — lib/logi-settings.py reads a temporary copy of Logi Options+'s
# settings.db (deleted afterwards; the real database is never opened) and compares the
# MX Master 3S values with lib/logi-expected.list.
check_logi() {  # comma-separated ids
  local ids="$1" py="" p out rc msgs
  if [ ! -d "${MANUAL_STEPS_LOGI_APP:-/Applications/logioptionsplus.app}" ]; then
    res warn "Logi Options+ not installed (brew bundle)"; return
  fi
  for p in "$(command -v python3 2>/dev/null)" /opt/homebrew/bin/python3 /usr/bin/python3; do
    if [ -n "$p" ] && [ -x "$p" ]; then py="$p"; break; fi
  done
  if [ -z "$py" ]; then res hand "python3 not found; check in Logi Options+"; return; fi
  if out="$(with_timeout 20 "$py" "$DOTDIR/lib/logi-settings.py" --only "$ids" </dev/null 2>&1)"; then rc=0; else rc=$?; fi
  case "$rc" in
    0) res ok "$(printf '%s\n' "$out" | awk -F'|' '$1 == "ok" { sub(/^[^|]*\|[^|]*\|/, ""); printf "%s%s", sep, $0; sep = "; " }')" ;;
    1) msgs="$(printf '%s\n' "$out" | awk -F'|' '$1 == "drift" || $1 == "warn" { sub(/^[^|]*\|[^|]*\|/, ""); printf "%s%s", sep, $0; sep = "; " }')"
       res warn "$msgs" ;;
    3) res warn "Logi Options+ settings not found (open the app once)" ;;
    *) msgs="$(printf '%s\n' "$out" | awk -F'|' '$1 == "error" { sub(/^[^|]*\|[^|]*\|/, ""); print; exit }')"
       res hand "can't read Logi Options+ settings (${msgs:-rc=$rc}); check in the app" ;;
  esac
}

run_check() {  # spec [id]
  local spec="$1" id="${2:-}" rest path line status detail
  case "$spec" in
    '')          res hand "" ;;
    '@macconfig-check.sh') res covered "verified by macconfig-check.sh" ;;
    @macconfig:*)
      # macconfig already ran the section. Do not run it again or count it twice.
      if [ "${MACCONFIG_OWNS_SECTIONS:-}" = 1 ]; then
        res covered "verified by macconfig-check.sh"
        return 0
      fi
      line="$(covered_step_run "$id" "${spec#@macconfig:}" 2>/dev/null || true)"
      status="${line%%|*}"
      detail="${line#*|}"
      detail="$(printf '%s' "$detail" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
      case "$status" in
        ok) res ok "$detail" ;;
        warn) res warn "$detail" ;;
        *)
          # Keep the check's own words. An empty detail would be printed as
          # "Can't check this automatically", which is only for a step with no check.
          if [ -n "$detail" ]; then
            res hand "$detail"
          else
            res hand "this check did not report a result"
          fi
          ;;
      esac
      ;;
    tcc:*)       rest="${spec#tcc:}"; check_tcc "${rest%%:*}" "${rest#*:}" ;;
    defaults:*)  rest="${spec#defaults:}"; check_defaults "${rest%%:*}" "${rest#*:}" ;;
    logi:*)      check_logi "${spec#logi:}" ;;
    app:*)
      path="${spec#app:}"; path="${path//@HOME@/$HOME}"
      if [ -e "$path" ]; then res ok "installed"; else res warn "not found at ${path/#$HOME/~}"; fi ;;
    hammerspoon-ax)   check_hammerspoon_ax ;;
    karabiner-driver) check_karabiner_driver ;;
    pointer-size)     check_pointer_size ;;
    input-british)    check_input_british ;;
    op-cli)           check_op_cli ;;
    gh-auth)          check_gh_auth ;;
    spotlight-results) check_spotlight_results ;;
    remove-widgets)   check_remove_widgets ;;
    edge-light)       check_edge_light ;;
    home-printer)     check_home_printer ;;
    tailscale-signin) check_tailscale_signin ;;
    whatsapp-web)     check_whatsapp_web ;;
    *)                res hand "unknown check '$spec'" ;;
  esac
}

# ---- commands -----------------------------------------------------------
# Blank line, then the group name. list, check, and open all use this.
group_heading() { printf '\n%s%s%s\n' "$C_HDR" "$1" "$C_OFF"; }

cmd_list() {
  local i num last="" auto
  if [ "${1:-}" = "--markdown" ]; then
    printf '| # | Step | Where | Checked |\n|---|------|------|------|\n'
    i=0
    while [ "$i" -lt "$N" ]; do
      case "${S_CHECK[$i]}" in
        # edge-light runs, but it cannot read the setting, so the row stays by hand.
        ''|edge-light) auto="by hand" ;;
        '@macconfig-check.sh'|@macconfig:*) auto="macconfig-check.sh" ;;
        *) auto="auto" ;;
      esac
      printf '| %d | %s | %s | %s |\n' "$((i + 1))" "${S_TITLE[$i]}" "${S_WHERE[$i]}" "$auto"
      i=$((i + 1))
    done
    return 0
  fi
  printf '%sManual steps%s (no script can do these; source: lib/manual-steps.list)\n' "$C_HDR" "$C_OFF"
  i=0
  while [ "$i" -lt "$N" ]; do
    if [ "${S_GROUP[$i]}" != "$last" ]; then
      group_heading "${S_GROUP[$i]}"; last="${S_GROUP[$i]}"
    fi
    num=$((i + 1))
    printf '  %2d. %s\n' "$num" "${S_TITLE[$i]}"
    printf '      %s%s%s\n' "$C_DIM" "${S_WHERE[$i]}" "$C_OFF"
    i=$((i + 1))
  done
  printf '\nscripts/manual-steps.sh check   shows which are already done (also part of ./macconfig-check.sh)\n'
  printf 'scripts/manual-steps.sh open    walks through the rest, opening each settings page\n'
}

# Why this step is on the walk-through. Uses the check just run (R_STATUS / R_DETAIL).
open_why() {
  case "$R_STATUS" in
    warn)
      if [ -n "$R_DETAIL" ]; then
        printf '%s' "Not set yet: $R_DETAIL"
      else
        printf '%s' "Not set yet"
      fi
      ;;
    ok|covered)
      printf '%s' "Already done, shown because of --all"
      ;;
    *)
      # Empty detail is a step with no check. A check always leaves its own
      # words here, including Edge Light and a step that is only partly covered.
      if [ -n "$R_DETAIL" ]; then
        printf '%s' "$R_DETAIL"
      else
        printf '%s' "Can't check this automatically. If it's already set, press s."
      fi
      ;;
  esac
}

# Steps that are not set, or that can't be checked. Same why-line as open.
# Already-done steps (ok, or covered) are counted and not printed.
cmd_pending() {
  local i num last="" skipped=0 shown=0 lead="" why_c=""
  printf '%sManual steps still to do%s\n' "$C_HDR" "$C_OFF"
  i=0
  while [ "$i" -lt "$N" ]; do
    num=$((i + 1))
    run_check "${S_CHECK[$i]}" "${S_ID[$i]}"
    if [ "$R_STATUS" = ok ] || [ "$R_STATUS" = covered ]; then
      skipped=$((skipped + 1))
      i=$((i + 1))
      continue
    fi
    shown=$((shown + 1))
    if [ "${S_GROUP[$i]}" != "$last" ]; then
      if [ -n "$last" ]; then printf '\n'; fi
      group_heading "${S_GROUP[$i]}"
      last="${S_GROUP[$i]}"
      lead=""
    else
      lead=$'\n'
    fi
    case "$R_STATUS" in
      warn) why_c="$C_WARN" ;;
      *) why_c="$C_DIM" ;;
    esac
    printf '%s%s%d. %s%s\n      %s%s%s\n      %s\n' \
      "$lead" "$C_HDR" "$num" "${S_TITLE[$i]}" "$C_OFF" \
      "$why_c" "$(open_why)" "$C_OFF" \
      "${S_WHERE[$i]}"
    i=$((i + 1))
  done
  echo
  if [ "$shown" = 0 ]; then
    echo "Nothing left to set by hand."
  fi
  printf 'Skipped %d already done.\n' "$skipped"
}

open_target() {  # target
  local t="$1"
  case "$t" in
    '')    return 0 ;;
    app:Fleet\ Desktop)
      # The self-service page needs the device id, which is not stored here.
      fleet_open_self_service || true
      ;;
    app:*) open -a "${t#app:}" 2>/dev/null || echo "      (couldn't open ${t#app:} — open it by hand)" ;;
    # https:// follows the default browser, which this repo sets to Chrome.
    # File → Add to Dock exists only in Safari, so a Safari web app must not
    # go through that default.
    safari:https://*)
      open -a Safari "${t#safari:}" 2>/dev/null || echo "      (couldn't open ${t#safari:} in Safari — open it by hand)"
      ;;
    *)     open "$t" 2>/dev/null || echo "      (couldn't open $t — open it by hand)" ;;
  esac
}

cmd_open() {
  local all=0 i num reply todo=0 last="" lead="" why_c=""
  [ "${1:-}" = "--all" ] && all=1
  # Tests set MANUAL_STEPS_OPEN_TTY=1 to drive the walk-through from a pipe.
  # A real run still requires a terminal, so a non-interactive caller does nothing.
  if [ ! -t 0 ] && [ "${MANUAL_STEPS_OPEN_TTY:-}" != 1 ]; then
    echo "manual-steps.sh open: stdin isn't a terminal — skipping the walk-through (run it from a terminal)."
    return 0
  fi
  command -v open >/dev/null 2>&1 || { echo "manual-steps.sh open: needs macOS 'open'." >&2; return 1; }
  echo "Walking through the manual steps. Enter = done/next, s = skip, q = quit."
  i=0
  while [ "$i" -lt "$N" ]; do
    num=$((i + 1))
    run_check "${S_CHECK[$i]}" "${S_ID[$i]}"
    if [ "$all" = 0 ]; then
      if [ "$R_STATUS" = ok ] || [ "$R_STATUS" = covered ]; then i=$((i + 1)); continue; fi
    fi
    todo=$((todo + 1))
    if [ "${S_GROUP[$i]}" != "$last" ]; then
      # The key prompt does not end with a newline, so a later group needs one
      # extra newline before the blank line that starts the heading. The first
      # heading follows the intro line, which already ended.
      if [ -n "$last" ]; then printf '\n'; fi
      group_heading "${S_GROUP[$i]}"
      last="${S_GROUP[$i]}"
      lead=""
    else
      lead=$'\n'
    fi
    case "$R_STATUS" in
      warn) why_c="$C_WARN" ;;
      *) why_c="$C_DIM" ;;
    esac
    printf '%s%s%d. %s%s\n      %s%s%s\n      %s\n' \
      "$lead" "$C_HDR" "$num" "${S_TITLE[$i]}" "$C_OFF" \
      "$why_c" "$(open_why)" "$C_OFF" \
      "${S_WHERE[$i]}"
    printf '      [Enter] open%s, s skip, q quit: ' "$([ -n "${S_OPEN[$i]}" ] || echo ' (nothing to open)')"
    read -r reply || reply=q
    case "$reply" in
      q|Q) echo "Stopped at step $num."; return 0 ;;
      s|S) i=$((i + 1)); continue ;;
    esac
    open_target "${S_OPEN[$i]}"
    printf '      Press Enter when done: '
    read -r reply || return 0
    i=$((i + 1))
  done
  if [ "$todo" = 0 ]; then echo "Nothing to do: every checkable step already passes (use --all to see them all)."; fi
  echo ""
  echo "Done. Run scripts/manual-steps.sh check (or ./macconfig-check.sh) to confirm."
}

cmd_check() {
  local porcelain=0 i num oks=0 warns=0 hands=0 covered=0 label colour msg last=""
  [ "${1:-}" = "--porcelain" ] && porcelain=1
  [ "$porcelain" = 1 ] || printf '%sManual steps — read-only checks%s\n' "$C_HDR" "$C_OFF"
  i=0
  while [ "$i" -lt "$N" ]; do
    num=$((i + 1))
    run_check "${S_CHECK[$i]}" "${S_ID[$i]}"
    case "$R_STATUS" in
      ok)      oks=$((oks + 1));         label="ok";       colour="$C_OK" ;;
      warn)    warns=$((warns + 1));     label="warn";     colour="$C_WARN" ;;
      covered) covered=$((covered + 1)); label="macconfig-check.sh"; colour="$C_DIM" ;;
      *)       hands=$((hands + 1));     label="by hand";  colour="$C_DIM"; R_STATUS=hand ;;
    esac
    if [ "$porcelain" = 1 ]; then
      # macconfig-check.sh reads status|num|id|title|detail. No headings here.
      printf '%s|%d|%s|%s|%s\n' "$R_STATUS" "$num" "${S_ID[$i]}" "${S_TITLE[$i]}" "$R_DETAIL"
    else
      if [ "${S_GROUP[$i]}" != "$last" ]; then
        group_heading "${S_GROUP[$i]}"; last="${S_GROUP[$i]}"
      fi
      msg="${S_TITLE[$i]}"
      [ -n "$R_DETAIL" ] && msg="$msg — $R_DETAIL"
      printf '  %s%-19s%s %2d. %s\n' "$colour" "$label" "$C_OFF" "$num" "$msg"
    fi
    i=$((i + 1))
  done
  if [ "$porcelain" = 0 ]; then
    printf '\n%sSummary:%s %d ok, %d warn, %d to check by hand, %d verified by macconfig-check.sh.\n' \
      "$C_HDR" "$C_OFF" "$oks" "$warns" "$hands" "$covered"
  fi
  [ "$warns" -eq 0 ]
}

cmd_validate() {
  if [ "${#ERRORS[@]}" -gt 0 ]; then
    printf '%s: %d problem(s)\n' "$LIST" "${#ERRORS[@]}" >&2
    printf '  %s\n' "${ERRORS[@]}" >&2
    return 1
  fi
  printf '%s: %d steps OK\n' "$LIST" "$N"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in -h|--help|'') usage; [ -n "$cmd" ]; return $? ;; esac
  shift
  case "$cmd" in
    list|pending|open|check|validate) ;;
    *) echo "Unknown command: $cmd (try --help)" >&2; return 2 ;;
  esac
  load_steps
  if [ "$cmd" != validate ] && [ "${#ERRORS[@]}" -gt 0 ]; then
    printf 'Warning: %d malformed row(s) in %s skipped (run: manual-steps.sh validate)\n' "${#ERRORS[@]}" "$LIST" >&2
  fi
  case "$cmd" in
    list)     cmd_list "$@" ;;
    pending)  cmd_pending ;;
    open)     cmd_open "$@" ;;
    check)    cmd_check "$@" ;;
    validate) cmd_validate ;;
  esac
}

main "$@"
