#!/usr/bin/env bash
#
# manual-steps.sh — the steps no script can do (privacy permissions, sign-ins, MDM
# apps, settings not exposed via `defaults`), read from lib/manual-steps.list.
#
#   list [--markdown]   numbered checklist (or a Markdown table for the README)
#   open [--all]        interactive walk-through: opens each step's settings page and
#                       waits for Enter. Skips steps whose check already passes unless
#                       --all. Does nothing when stdin isn't a terminal.
#   check [--porcelain] run each step's read-only check: ok / warn / check by hand.
#                       --porcelain prints status|num|id|title|detail for check.sh.
#                       Exit status: 1 if any automated check warns, else 0.
#   validate            parse the list and report malformed rows (used by tests/).
#
# Read-only: never writes a setting, and every slow call is wrapped in a timeout so a
# check can't hang or prompt. Bash 3.2-safe (stock macOS bash).
#
set -uo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="${MANUAL_STEPS_LIST:-$DOTDIR/lib/manual-steps.list}"
TCC_DB="${MANUAL_STEPS_TCC_DB:-/Library/Application Support/com.apple.TCC/TCC.db}"
NAMED_CHECKS=" hammerspoon-ax karabiner-driver pointer-size input-british op-cli gh-auth "

usage() {
  cat <<'USAGE'
Usage: scripts/manual-steps.sh <command> [option]
  list [--markdown]    Print the manual steps as a numbered checklist (or Markdown table).
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
      ''|x-apple.systempreferences:?*|https://?*|macappstore://*|app:?*) ;;
      *) ERRORS+=("line $lineno: open '$target' must be x-apple.systempreferences:, https://, macappstore:// or app:") ;;
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
    ''|'@check.sh') return 0 ;;
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

check_defaults() {  # domain k=v[,k=v]
  local domain="$1" pairs="$2" pair key want cur bad="" ok=""
  if ! defaults read "$domain" >/dev/null 2>&1; then
    res hand "can't read $domain"; return
  fi
  local IFS=','
  for pair in $pairs; do
    key="${pair%%=*}"; want="${pair#*=}"
    if cur="$(defaults read "$domain" "$key" 2>/dev/null)"; then
      if [ "$cur" = "$want" ]; then ok="$ok $key=$cur"; else bad="$bad $key=$cur (want $want)"; fi
    else
      bad="$bad $key not set (want $want)"
    fi
  done
  if [ -n "$bad" ]; then res warn "${bad# }"; else res ok "${ok# }"; fi
}

check_hammerspoon_ax() {
  if [ ! -d /Applications/Hammerspoon.app ]; then res warn "Hammerspoon.app not installed (brew bundle)"; return; fi
  if pgrep -xq Hammerspoon && command -v hs >/dev/null 2>&1; then
    # -q: result only; -t: IPC timeout. </dev/null matters: hs reads stdin when it's a
    # pipe (launchd/agent runs) and would otherwise wait forever.
    case "$(with_timeout 6 hs -q -t 3 -c 'hs.accessibilityState()' </dev/null 2>/dev/null)" in
      true)  res ok "granted (live, via hs)"; return ;;
      false) res warn "not granted — enable it, then restart Hammerspoon"; return ;;
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
# terminal session has already authorised. Success proves the integration works;
# failure just means "not authorised here", so that's check by hand, not a warning.
check_op_cli() {
  if [ ! -d /Applications/1Password.app ]; then res warn "1Password.app not installed (Iru Self Service)"; return; fi
  if ! command -v op >/dev/null 2>&1; then res warn "op CLI not installed (brew bundle)"; return; fi
  if with_timeout 8 op whoami </dev/null >/dev/null 2>&1; then
    res ok "op whoami works through the app"
  else
    res hand "not authorised in this session; run op whoami in a terminal to confirm"
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

run_check() {  # spec
  local spec="$1" rest path
  case "$spec" in
    '')          res hand "" ;;
    '@check.sh') res covered "verified by check.sh" ;;
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
    *)                res hand "unknown check '$spec'" ;;
  esac
}

# ---- commands -----------------------------------------------------------
cmd_list() {
  local i num last="" auto
  if [ "${1:-}" = "--markdown" ]; then
    printf '| # | Step | Where | Checked |\n|---|------|------|------|\n'
    i=0
    while [ "$i" -lt "$N" ]; do
      case "${S_CHECK[$i]}" in '') auto="by hand" ;; '@check.sh') auto="check.sh" ;; *) auto="auto" ;; esac
      printf '| %d | %s | %s | %s |\n' "$((i + 1))" "${S_TITLE[$i]}" "${S_WHERE[$i]}" "$auto"
      i=$((i + 1))
    done
    return 0
  fi
  printf '%sManual steps%s (no script can do these; source: lib/manual-steps.list)\n' "$C_HDR" "$C_OFF"
  i=0
  while [ "$i" -lt "$N" ]; do
    if [ "${S_GROUP[$i]}" != "$last" ]; then
      printf '\n%s%s%s\n' "$C_HDR" "${S_GROUP[$i]}" "$C_OFF"; last="${S_GROUP[$i]}"
    fi
    num=$((i + 1))
    printf '  %2d. %s\n' "$num" "${S_TITLE[$i]}"
    printf '      %s%s%s\n' "$C_DIM" "${S_WHERE[$i]}" "$C_OFF"
    i=$((i + 1))
  done
  printf '\nscripts/manual-steps.sh check   shows which are already done (also part of ./check.sh)\n'
  printf 'scripts/manual-steps.sh open    walks through the rest, opening each settings page\n'
}

open_target() {  # target
  local t="$1"
  case "$t" in
    '')    return 0 ;;
    app:*) open -a "${t#app:}" 2>/dev/null || echo "      (couldn't open ${t#app:} — open it by hand)" ;;
    *)     open "$t" 2>/dev/null || echo "      (couldn't open $t — open it by hand)" ;;
  esac
}

cmd_open() {
  local all=0 i num reply todo=0
  [ "${1:-}" = "--all" ] && all=1
  if [ ! -t 0 ]; then
    echo "manual-steps.sh open: stdin isn't a terminal — skipping the walk-through (run it from a terminal)."
    return 0
  fi
  command -v open >/dev/null 2>&1 || { echo "manual-steps.sh open: needs macOS 'open'." >&2; return 1; }
  echo "Walking through the manual steps. Enter = done/next, s = skip, q = quit."
  i=0
  while [ "$i" -lt "$N" ]; do
    num=$((i + 1))
    if [ "$all" = 0 ]; then
      run_check "${S_CHECK[$i]}"
      if [ "$R_STATUS" = ok ] || [ "$R_STATUS" = covered ]; then i=$((i + 1)); continue; fi
    fi
    todo=$((todo + 1))
    printf '\n%s%d. %s%s\n      %s\n' "$C_HDR" "$num" "${S_TITLE[$i]}" "$C_OFF" "${S_WHERE[$i]}"
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
  echo "Done. Run scripts/manual-steps.sh check (or ./check.sh) to confirm."
}

cmd_check() {
  local porcelain=0 i num oks=0 warns=0 hands=0 covered=0 label colour msg
  [ "${1:-}" = "--porcelain" ] && porcelain=1
  [ "$porcelain" = 1 ] || printf '%sManual steps — read-only checks%s\n' "$C_HDR" "$C_OFF"
  i=0
  while [ "$i" -lt "$N" ]; do
    num=$((i + 1))
    run_check "${S_CHECK[$i]}"
    case "$R_STATUS" in
      ok)      oks=$((oks + 1));         label="ok";       colour="$C_OK" ;;
      warn)    warns=$((warns + 1));     label="warn";     colour="$C_WARN" ;;
      covered) covered=$((covered + 1)); label="check.sh"; colour="$C_DIM" ;;
      *)       hands=$((hands + 1));     label="by hand";  colour="$C_DIM"; R_STATUS=hand ;;
    esac
    if [ "$porcelain" = 1 ]; then
      printf '%s|%d|%s|%s|%s\n' "$R_STATUS" "$num" "${S_ID[$i]}" "${S_TITLE[$i]}" "$R_DETAIL"
    else
      msg="${S_TITLE[$i]}"
      [ -n "$R_DETAIL" ] && msg="$msg — $R_DETAIL"
      printf '  %s%-9s%s %2d. %s\n' "$colour" "$label" "$C_OFF" "$num" "$msg"
    fi
    i=$((i + 1))
  done
  if [ "$porcelain" = 0 ]; then
    printf '\n%sSummary:%s %d ok, %d warn, %d to check by hand, %d verified by check.sh.\n' \
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
    list|open|check|validate) ;;
    *) echo "Unknown command: $cmd (try --help)" >&2; return 2 ;;
  esac
  load_steps
  if [ "$cmd" != validate ] && [ "${#ERRORS[@]}" -gt 0 ]; then
    printf 'Warning: %d malformed row(s) in %s skipped (run: manual-steps.sh validate)\n' "${#ERRORS[@]}" "$LIST" >&2
  fi
  case "$cmd" in
    list)     cmd_list "$@" ;;
    open)     cmd_open "$@" ;;
    check)    cmd_check "$@" ;;
    validate) cmd_validate ;;
  esac
}

main "$@"
