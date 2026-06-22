#!/usr/bin/env bash
#
# macos.sh — apply a curated, idempotent set of macOS `defaults`.
#
# Reads current state first, then per setting:
#   present, type mismatch    -> WARN, skip (never clobber a wrong-typed value)
#   present, type ok, equal   -> re-assert (write same value), log "already set"
#   present, type ok, differs -> write, log "changed: old -> new"
#   missing                   -> write, log "set (was unset)"
#
# A "set (was unset)" on a machine you've already configured can be an early
# hint that a macOS upgrade renamed or moved a key — check the run report.
#
# Flags:
#   --dry-run   Show every decision, write nothing, take no backups.
#   --no-color  Disable ANSI colour (also honours the NO_COLOR env var).
#   --list      Print the managed settings as a Markdown table and exit.
#   -h|--help   Show usage.
#
# Safety:
#   - No sudo. sudo-only items (e.g. hostname) stay manual (see README).
#   - Before the first value-changing write, every affected domain is exported
#     to backups/defaults-<timestamp>/ (gitignored). Reverse with `defaults import`.
#   - UI restarts (killall) are deferred to the end, run only if something
#     changed, and only after you confirm at the prompt.
#
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
NO_COLOR_OPT=0
LIST=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)  DRY_RUN=1 ;;
    --no-color) NO_COLOR_OPT=1 ;;
    --list)     LIST=1 ;;
    -h|--help)
      cat <<'USAGE'
Usage: macos.sh [--dry-run] [--no-color] [--list]
  --dry-run    Show every decision, write nothing, take no backups.
  --no-color   Disable ANSI colour (also honours the NO_COLOR env var).
  --list       Print the managed settings as a Markdown table and exit.
  -h, --help   Show this help.
USAGE
      exit 0 ;;
    *) echo "Unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

# ---- logging (colour only on a tty) -------------------------------------
if [ -t 1 ] && [ "$NO_COLOR_OPT" != 1 ] && [ -z "${NO_COLOR+x}" ]; then
  C_OK=$'\033[32m'; C_CHG=$'\033[36m'; C_WARN=$'\033[33m'; C_OFF=$'\033[0m'
else
  C_OK=''; C_CHG=''; C_WARN=''; C_OFF=''
fi
say_ok()   { printf '  %sok%s    %s\n' "$C_OK"   "$C_OFF" "$1"; }
say_chg()  { printf '  %schg%s   %s\n' "$C_CHG"  "$C_OFF" "$1"; }
say_warn() { printf '  %swarn%s  %s\n' "$C_WARN" "$C_OFF" "$1"; }

CONSIDERED=0
CHANGED=0
REASSERTED=0
WARNINGS=0
RESTARTS=''
NEEDS_LOGOUT=0
LOGOUT_ITEMS=''
NL=$'\n'
BACKED_UP=0

# ---- helpers ------------------------------------------------------------
# Value-comparison helpers (norm_bool, values_equal, type_token) live in a shared
# lib so check.sh can reuse the exact same match semantics.
# shellcheck source=lib/defaults-lib.sh disable=SC1091
. "$DOTDIR/lib/defaults-lib.sh"

queue_restart() {  # restart-token  [descriptor]
  [ -z "$1" ] && return 0
  if [ "$1" = logout ]; then
    NEEDS_LOGOUT=1
    LOGOUT_ITEMS="${LOGOUT_ITEMS}${LOGOUT_ITEMS:+$NL}${2:-a setting}"
    return 0
  fi
  case " $RESTARTS " in
    *" $1 "*) : ;;
    *) RESTARTS="$RESTARTS $1" ;;
  esac
}

BACKUP_DOMAINS='NSGlobalDomain com.apple.dock com.apple.finder com.apple.screencapture com.apple.menuextra.clock'

ensure_backup() {  # export pre-change state once, before the first real write
  [ "$BACKED_UP" = 1 ] && return 0
  BACKED_UP=1
  local dir d
  dir="$DOTDIR/backups/defaults-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$dir"
  for d in $BACKUP_DOMAINS; do
    defaults export "$d" "$dir/$d.plist" 2>/dev/null || say_warn "could not back up $d"
  done
  printf '  backups -> %s\n' "$dir"
}

write_default() {  # domain key type value
  local flag
  case "$3" in
    string) flag=-string ;;
    float)  flag=-float ;;
    int)    flag=-int ;;
    bool)   flag=-bool ;;
  esac
  defaults write "$1" "$2" "$flag" "$4"
}

apply_setting() {  # domain key type desired restart
  local domain="$1" key="$2" etype="$3" desired="$4" restart="$5"
  CONSIDERED=$((CONSIDERED + 1))
  desired="${desired//@HOME@/$HOME}"
  local cur curtype want_token
  want_token="$(type_token "$etype")"

  if cur="$(defaults read "$domain" "$key" 2>/dev/null)"; then
    curtype="$(defaults read-type "$domain" "$key" 2>/dev/null || true)"
    curtype="${curtype##* }"   # "Type is boolean" -> "boolean"
    if [ "$curtype" != "$want_token" ]; then
      say_warn "$domain $key — type mismatch (expected $want_token, found ${curtype:-none}); skipping"
      WARNINGS=$((WARNINGS + 1))
      return 0
    fi
    if values_equal "$etype" "$cur" "$desired"; then
      if [ "$DRY_RUN" = 1 ]; then
        say_ok "$domain $key — would re-assert (already set: $cur)"
      else
        write_default "$domain" "$key" "$etype" "$desired"
        say_ok "$domain $key — re-asserted (already set: $cur)"
      fi
      REASSERTED=$((REASSERTED + 1))
      return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
      say_chg "$domain $key — would change: $cur -> $desired"
    else
      ensure_backup
      write_default "$domain" "$key" "$etype" "$desired"
      say_chg "$domain $key — changed: $cur -> $desired"
    fi
  else
    if [ "$DRY_RUN" = 1 ]; then
      say_chg "$domain $key — would set (was unset) -> $desired"
    else
      ensure_backup
      write_default "$domain" "$key" "$etype" "$desired"
      say_chg "$domain $key — set (was unset) -> $desired"
    fi
  fi
  CHANGED=$((CHANGED + 1))
  queue_restart "$restart" "$domain $key"
}

# ---- settings table -----------------------------------------------------
# The managed settings live in lib/macos-defaults.list (one pipe-delimited row per
# setting; see that file's header for the format). Loaded here so the list is a single
# source of truth shared with check.sh. Blank/# lines are skipped by the read loops.
SETTINGS="$(<"$DOTDIR/lib/macos-defaults.list")"

# shellcheck disable=SC2016  # printf formats below contain literal Markdown backticks; single quotes intentional (no expansion wanted)
list_settings() {
  printf '| Area | Setting | `defaults` key | Value |\n'
  printf '|------|------|------|------|\n'
  while IFS='|' read -r domain key etype desired restart area label disp; do
    case "$domain" in ''|'#'*) continue ;; esac
    printf '| %s | %s | `%s %s` | %s |\n' "$area" "$label" "$domain" "$key" "$disp"
  done <<< "$SETTINGS"
}

[ "$LIST" = 1 ] && { list_settings; exit 0; }

echo "macos.sh — $([ "$DRY_RUN" = 1 ] && echo 'DRY RUN (no writes)' || echo 'applying')"
echo

while IFS='|' read -r domain key etype desired restart area label disp; do
  case "$domain" in ''|'#'*) continue ;; esac
  apply_setting "$domain" "$key" "$etype" "$desired" "$restart"
done <<< "$SETTINGS"

echo
echo "Summary: $CONSIDERED setting(s) checked, $CHANGED changed, $REASSERTED re-asserted, $WARNINGS warning(s)."

# ---- deferred UI restarts (only if something changed) -------------------
if [ "$DRY_RUN" != 1 ] && [ "$CHANGED" -gt 0 ] && [ -n "${RESTARTS// /}" ]; then
  echo
  printf 'Restart now to apply:%s ? [y/N] ' "$RESTARTS"
  read -r reply || reply=''
  case "$reply" in
    y|Y|yes|YES)
      # shellcheck disable=SC2086  # intentional: $RESTARTS is a space-separated list we want word-split
      for p in $RESTARTS; do
        killall "$p" 2>/dev/null && echo "  restarted $p" || echo "  $p not running"
      done ;;
    *) echo '  skipped — changes apply at next login.' ;;
  esac
fi

if [ "$NEEDS_LOGOUT" = 1 ] && [ "$CHANGED" -gt 0 ]; then
  echo
  echo 'Note: the following changed and may need a logout/login to fully apply:'
  while IFS= read -r item; do
    [ -n "$item" ] && printf '  - %s\n' "$item"
  done <<< "$LOGOUT_ITEMS"
fi

cat <<'MANUAL'

Still manual (not scriptable / out of scope) — see README:
  - Apple Account sign-in; User & Groups account picture
  - Displays "More Space"; Keyboard British input source
  - Mouse + Trackpad speeds / natural scrolling (managed via Logi Options+)
  - Accessibility grants (TCC); Notifications; Spotlight result categories
  - Finder sidebar "Show Recents"
  - Set Hostname (requires sudo)
MANUAL
