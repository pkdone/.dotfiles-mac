#!/usr/bin/env bash
#
# macos.sh — apply a curated, idempotent set of macOS `defaults`.
#
# Reads current state first, then per setting:
#   present, bool and int 0/1, same value -> equal. A re-assert uses the type
#                                 already stored, so a boolean stays a boolean.
#   present, bool and int 0/1, different  -> write in the type already stored
#   present, other type mismatch          -> WARN, skip (never clobber a wrong-typed value)
#   present, type ok, equal               -> re-assert (write same value), log "already set"
#   present, type ok, differs             -> write, log "changed: old -> new"
#   missing                               -> write, log "set (was unset)"
#
# A "set (was unset)" on a machine you've already configured can be an early
# hint that a macOS upgrade renamed or moved a key — check the run report.
#
# Flags:
#   --dry-run   Show every decision, write nothing, take no backups.
#   --no-color  Disable ANSI colour (also honours the NO_COLOR env var).
#   --list      Print the managed settings as a Markdown table and exit.
#   --only ID   Apply only this item (repeatable): a "domain|key" row from
#               lib/macos-defaults.list, or @dictation-164 / @quicknote-190 / @coteditor /
#               @finder-recents / @finder-icon-view / @finder-favorites /
#               @finder-show / @titlebar-double-click / @ac-sleep /
#               @display-more-space. Values that already match are left alone
#               (no re-assert write). @finder-favorites only reads the sidebar
#               file. Used by `macconfig-check.sh --fix`.
#   --yes       Run the deferred UI restarts without prompting (still only if
#               something changed). Also skips the AC-sleep confirmation and goes
#               straight to sudo when a terminal can ask for a password. Used by
#               `macconfig-check.sh --fix` (that path never passes @ac-sleep).
#   -h|--help   Show usage.
#
# Safety:
#   - sudo is only used for power, and only for the pmset commands that are
#     still wrong: AC sleep 0, AC display sleep 10 minutes, battery display
#     sleep 2 minutes, and AC wake for network access (womp 1). Skipped when
#     sudo isn't available (no passwordless sudo and no terminal) or isn't
#     wanted (--dry-run, or you answer no). Values that already match do not
#     call sudo. Battery idle sleep is not changed. Closing the lid still
#     sleeps the Mac. Other sudo-only items (hostname, display auto-brightness)
#     stay manual. macconfig --fix never selects @ac-sleep.
#   - Dark mode is also applied live with System Events when it is not already
#     on. A missing Automation permission is a warning, not a failure, and does
#     not ask for a logout.
#   - After a trackpad value changes, activateSettings -u reloads it when that
#     tool is present, so those rows do not ask for a logout. If it is missing
#     or fails, they stay on the logout list.
#   - @display-more-space sets the built-in panel with displayplacer. External
#     displays are passed through unchanged. A missing tool or mode is a warning
#     and stays the manual step.
#   - Before the first value-changing write, every affected domain is exported
#     to backups/defaults-<timestamp>/ (gitignored). Reverse with `defaults import`.
#   - UI restarts (killall) are deferred to the end, run only if something
#     changed, and only after you confirm at the prompt.
#   - com.apple.screencapture location: mkdir -p ~/Pictures/Screenshots before
#     the write (also when macconfig-check.sh --fix calls this with --only).
#     Existing files are not moved. install.sh creates the same folder.
#
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
NO_COLOR_OPT=0
LIST=0
YES=0
NL=$'\n'
ONLY_IDS=''      # newline-separated --only ids; empty = apply everything
ONLY_MATCHED=''

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)  DRY_RUN=1 ;;
    --no-color) NO_COLOR_OPT=1 ;;
    --list)     LIST=1 ;;
    --yes)      YES=1 ;;
    --only)
      if [ $# -lt 2 ]; then echo "--only needs an id (try --help)" >&2; exit 2; fi
      shift; ONLY_IDS="${ONLY_IDS}${ONLY_IDS:+$NL}$1" ;;
    --only=*)   ONLY_IDS="${ONLY_IDS}${ONLY_IDS:+$NL}${1#--only=}" ;;
    -h|--help)
      cat <<'USAGE'
Usage: macos.sh [--dry-run] [--no-color] [--list] [--only ID]... [--yes]
  --dry-run    Show every decision, write nothing, take no backups.
  --no-color   Disable ANSI colour (also honours the NO_COLOR env var).
  --list       Print the managed settings as a Markdown table and exit.
  --only ID    Apply only this item (repeatable): "domain|key" from
               lib/macos-defaults.list, or @dictation-164, @quicknote-190, @coteditor,
               @finder-recents, @finder-icon-view, @finder-favorites, @finder-show,
               @titlebar-double-click, @ac-sleep, @display-more-space. Matching
               values are left alone. Dark mode is also turned on live when it
               is not already on. A changed trackpad setting is reloaded with
               activateSettings when that tool is present.
               @finder-favorites reads the sidebar file and does not change it.
  --yes        Restart Dock/Finder/SystemUIServer/ControlCenter without prompting
               (only if something changed). Also accept the power sudo step
               without a separate confirmation (still skipped when sudo
               cannot run).
  -h, --help   Show this help.
USAGE
      exit 0 ;;
    *) echo "Unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

# selected ID — true if ID should be applied (no --only given, or ID was named).
# A hit is recorded so an unknown --only id can be reported at the end.
selected() {
  if [ -z "$ONLY_IDS" ]; then return 0; fi
  case "$NL$ONLY_IDS$NL" in
    *"$NL$1$NL"*) ONLY_MATCHED="${ONLY_MATCHED}${ONLY_MATCHED:+$NL}$1"; return 0 ;;
  esac
  return 1
}

# wants ID — same question, without recording a match. Used when the settings
# loop has already called selected for this id.
wants() {
  if [ -z "$ONLY_IDS" ]; then return 0; fi
  case "$NL$ONLY_IDS$NL" in
    *"$NL$1$NL"*) return 0 ;;
  esac
  return 1
}

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
BACKED_UP=0

# ---- helpers ------------------------------------------------------------
# Fail early with a clear message if a required data/helper file is missing.
require_file() { [ -r "$1" ] || { echo "Error: required file not found: $1" >&2; exit 1; }; }
for f in defaults-lib.sh macos-defaults.list; do require_file "$DOTDIR/lib/$f"; done

# Value-comparison helpers (norm_bool, values_equal, type_token) live in a shared
# lib so macconfig-check.sh can reuse the exact same match semantics.
# shellcheck source=lib/defaults-lib.sh disable=SC1091
. "$DOTDIR/lib/defaults-lib.sh"
# shellcheck source=lib/dotfiles-log.sh disable=SC1091
. "$DOTDIR/lib/dotfiles-log.sh"
DOT_PYTHON="$(dot_python || true)"

queue_restart() {  # restart-token  [descriptor]  [class]
  # class "trackpad" marks a row activateSettings can reload. Anything else
  # stays "other" and still needs a logout when it changes.
  [ -z "$1" ] && return 0
  if [ "$1" = logout ]; then
    local desc="${2:-a setting}" class="${3:-other}" row
    case "$class" in
      trackpad) ;;
      *) class=other ;;
    esac
    row="${class}|${desc}"
    NEEDS_LOGOUT=1
    LOGOUT_ITEMS="${LOGOUT_ITEMS}${LOGOUT_ITEMS:+$NL}${row}"
    return 0
  fi
  case " $RESTARTS " in
    *" $1 "*) : ;;
    *) RESTARTS="$RESTARTS $1" ;;
  esac
}

# BACKUP_DOMAINS (the domains exported before the first change) is derived from the
# settings list further below, so a setting in a new domain is covered automatically.
ensure_backup() {  # export pre-change state once, before the first real write
  [ "$BACKED_UP" = 1 ] && return 0
  BACKED_UP=1
  local dir d
  dir="$DOTDIR/backups/defaults-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$dir"
  for d in $BACKUP_DOMAINS; do
    defaults_export "$d" "$dir/$(defaults_domain "$d").plist" 2>/dev/null || say_warn "could not back up $d"
  done
  printf '  backups -> %s\n' "$dir"
}

# Domains may be prefixed with @host/ to use `defaults -currentHost` (ByHost plists).
defaults_domain() {  # domain -> prints bare domain
  case "$1" in @host/*) printf '%s' "${1#@host/}" ;; *) printf '%s' "$1" ;; esac
}
defaults_read() {  # domain key
  case "$1" in
    @host/*) defaults -currentHost read "${1#@host/}" "$2" ;;
    *)       defaults read "$1" "$2" ;;
  esac
}
defaults_read_type() {  # domain key
  case "$1" in
    @host/*) defaults -currentHost read-type "${1#@host/}" "$2" ;;
    *)       defaults read-type "$1" "$2" ;;
  esac
}
defaults_export() {  # domain outfile
  case "$1" in
    @host/*) defaults -currentHost export "${1#@host/}" "$2" ;;
    *)       defaults export "$1" "$2" ;;
  esac
}

write_default() {  # domain key type value
  local flag bare
  case "$3" in
    string) flag=-string ;;
    float)  flag=-float ;;
    int)    flag=-int ;;
    bool)   flag=-bool ;;
  esac
  bare="$(defaults_domain "$1")"
  case "$1" in
    @host/*) defaults -currentHost write "$bare" "$2" "$flag" "$4" ;;
    *)       defaults write "$bare" "$2" "$flag" "$4" ;;
  esac
}

# Screenshot location names a directory. Create it before the write, and again
# when the value already matches, so the default never points at a missing folder.
# Dry-run creates nothing. Existing files are not moved. install.sh creates it too.
# SCREENSHOT_DIR_ACTION is "" | created | would-create for the setting just prepared.
# SCREENSHOT_DIR_SHOWN is that path with $HOME written as ~ (a literal tilde).
SCREENSHOT_DIR_ACTION=""
SCREENSHOT_DIR_SHOWN=""
ensure_screenshot_dir() {  # domain key path
  SCREENSHOT_DIR_ACTION=""
  SCREENSHOT_DIR_SHOWN=""
  [ "$1" = com.apple.screencapture ] && [ "$2" = location ] || return 0
  local rest="${3#"$HOME"}"
  SCREENSHOT_DIR_SHOWN="~${rest}"
  [ -d "$3" ] && return 0
  if [ "$DRY_RUN" = 1 ]; then
    SCREENSHOT_DIR_ACTION=would-create
    say_chg "screenshot folder $SCREENSHOT_DIR_SHOWN — would mkdir -p"
    return 0
  fi
  mkdir -p "$3"
  SCREENSHOT_DIR_ACTION=created
  say_chg "screenshot folder $SCREENSHOT_DIR_SHOWN — created"
}

apply_setting() {  # domain key type desired restart tol [class]
  local domain="$1" key="$2" etype="$3" desired="$4" restart="$5" tol="${6:-}" class="${7:-}"
  CONSIDERED=$((CONSIDERED + 1))
  desired="${desired//@HOME@/$HOME}"
  ensure_screenshot_dir "$domain" "$key" "$desired"
  local cur curtype want_token write_type write_value
  want_token="$(type_token "$etype")"

  if cur="$(defaults_read "$domain" "$key" 2>/dev/null)"; then
    curtype="$(defaults_read_type "$domain" "$key" 2>/dev/null || true)"
    curtype="${curtype##* }"   # "Type is boolean" -> "boolean"
    # Boolean true is integer 1, and boolean false is integer 0. A fresh Mac
    # stores some 0/1 keys (the trackpad, video capture) as booleans while the
    # list says int. That is the same value. A difference is written with the
    # type already stored, so -bool stays -bool. Other integers are not booleans.
    if flex_01_applicable "$curtype" "$etype" "$cur" "$desired"; then
      write_type="$(flex_01_write_type "$curtype")"
      write_value="$(flex_01_write_value "$write_type" "$desired")"
      if flex_01_values_match "$cur" "$desired"; then
        if [ "$DRY_RUN" = 1 ]; then
          say_ok "$domain $key — would re-assert (already set: $cur)"
        elif [ -n "$ONLY_IDS" ]; then
          if [ "$SCREENSHOT_DIR_ACTION" = created ]; then
            say_ok "$domain $key — already set: $cur (mkdir -p $SCREENSHOT_DIR_SHOWN)"
          else
            say_ok "$domain $key — already set: $cur (left alone)"
          fi
        else
          write_default "$domain" "$key" "$write_type" "$write_value"
          say_ok "$domain $key — re-asserted (already set: $cur)"
        fi
        REASSERTED=$((REASSERTED + 1))
        return 0
      fi
      if [ "$DRY_RUN" = 1 ]; then
        say_chg "$domain $key — would change: $cur -> $desired"
      else
        ensure_backup
        write_default "$domain" "$key" "$write_type" "$write_value"
        say_chg "$domain $key — changed: $cur -> $desired"
      fi
      CHANGED=$((CHANGED + 1))
      queue_restart "$restart" "$domain $key" "$class"
      return 0
    fi
    if [ "$curtype" != "$want_token" ]; then
      say_warn "$domain $key — type mismatch (expected $want_token, found ${curtype:-none}); skipping"
      WARNINGS=$((WARNINGS + 1))
      return 0
    fi
    if values_match "$etype" "$cur" "$desired" "$tol"; then
      if [ -n "$tol" ] && [ "$tol" != 0 ] && ! values_equal "$etype" "$cur" "$desired"; then
        # within the allowed ±tol but not the exact ideal — accept the in-range value as-is
        say_ok "$domain $key — ok (within ±$tol of $desired): $cur"
        REASSERTED=$((REASSERTED + 1))
        return 0
      fi
      if [ "$DRY_RUN" = 1 ]; then
        say_ok "$domain $key — would re-assert (already set: $cur)"
      elif [ -n "$ONLY_IDS" ]; then
        if [ "$SCREENSHOT_DIR_ACTION" = created ]; then
          say_ok "$domain $key — already set: $cur (mkdir -p $SCREENSHOT_DIR_SHOWN)"
        else
          say_ok "$domain $key — already set: $cur (left alone)"
        fi
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
  queue_restart "$restart" "$domain $key" "$class"
}

# ---- settings table -----------------------------------------------------
# The managed settings live in lib/macos-defaults.list (one pipe-delimited row per
# setting; see that file's header for the format). Loaded here so the list is a single
# source of truth shared with macconfig-check.sh. Blank/# lines are skipped by the read loops.
SETTINGS="$(<"$DOTDIR/lib/macos-defaults.list")"

# Domains backed up before the first change = the unique set of domains the list
# touches (field 1), derived so a new-domain setting needs no edit to this script.
BACKUP_DOMAINS="$(awk -F'|' '$1 !~ /^#/ && NF {print $1}' <<< "$SETTINGS" | sort -u | tr '\n' ' ')"

# shellcheck disable=SC2016  # printf formats below contain literal Markdown backticks; single quotes intentional (no expansion wanted)
list_settings() {
  printf '| Area | Setting | `defaults` key | Value |\n'
  printf '|------|------|------|------|\n'
  while IFS='|' read -r domain key etype desired restart area label disp tol; do
    case "$domain" in ''|'#'*) continue ;; esac
    printf '| %s | %s | `%s %s` | %s |\n' "$area" "$label" "$domain" "$key" "$disp"
  done <<< "$SETTINGS"
}

[ "$LIST" = 1 ] && { list_settings; exit 0; }

if [ "$DRY_RUN" = 1 ]; then MODE='DRY RUN (no writes)'; else MODE='applying'; fi
if [ -n "$ONLY_IDS" ]; then MODE="$MODE — only: $(printf '%s' "$ONLY_IDS" | tr '\n' ',' | sed 's/,/, /g')"; fi
echo "macos.sh — $MODE"
echo

while IFS='|' read -r domain key etype desired restart area label disp tol; do
  case "$domain" in ''|'#'*) continue ;; esac
  selected "$domain|$key" || continue
  class=""
  if [ "$area" = Trackpad ]; then class=trackpad; fi
  apply_setting "$domain" "$key" "$etype" "$desired" "$restart" "$tol" "$class"
done <<< "$SETTINGS"

# ---- dark mode, live (System Events) ------------------------------------
# AppleInterfaceStyle is written above. That default does not switch the menu
# bar until logout, so when dark mode is not already on, ask System Events.
# A missing Automation permission is a warning. macconfig --fix reaches this
# through the same --only path as the default.
apply_dark_mode_live() {
  local current dark_get dark_set
  dark_get='tell application "System Events" to tell appearance preferences to get dark mode'
  dark_set='tell application "System Events" to tell appearance preferences to set dark mode to true'
  if ! command -v osascript >/dev/null 2>&1; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "osascript is not available, so dark mode was not switched on live. AppleInterfaceStyle is still written."
    return 0
  fi
  if ! current="$(osascript -e "$dark_get" 2>/dev/null)"; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "could not read dark mode (System Events failed, often a missing Automation permission). AppleInterfaceStyle is still written. The menu bar may stay light until that permission is allowed."
    return 0
  fi
  current="$(printf '%s' "$current" | tr -d '[:space:]')"
  case "$current" in
    true|True|TRUE)
      say_ok "dark mode already on"
      return 0
      ;;
  esac
  if [ "$DRY_RUN" = 1 ]; then
    CHANGED=$((CHANGED + 1))
    say_chg "would turn dark mode on now (System Events)"
    return 0
  fi
  if osascript -e "$dark_set" 2>/dev/null; then
    CHANGED=$((CHANGED + 1))
    say_chg "dark mode turned on (System Events)"
  else
    WARNINGS=$((WARNINGS + 1))
    say_warn "could not turn dark mode on (System Events failed, often a missing Automation permission). AppleInterfaceStyle is still written. Allow Automation for this terminal, or log out and back in."
  fi
}
if wants "NSGlobalDomain|AppleInterfaceStyle"; then apply_dark_mode_live; fi

# ---- trackpad: reload user settings so a logout is not required ----------
# One activateSettings -u covers every trackpad row that changed. Success
# drops those rows from the logout list. A missing or failing tool leaves
# them there. The values themselves are unchanged (bottom-right secondary
# click, TrackpadRightClick=0).
activate_trackpad_settings() {
  local bin item any=0
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    case "$item" in
      trackpad\|*) any=1 ;;
    esac
  done <<< "$LOGOUT_ITEMS"
  [ "$any" = 1 ] || return 0
  if [ -n "${DOTFILES_ACTIVATE_SETTINGS+x}" ]; then
    bin="$DOTFILES_ACTIVATE_SETTINGS"
  else
    bin="/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
  fi
  if [ ! -x "$bin" ]; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "activateSettings is not available — trackpad changes need a logout to apply"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    say_chg "would run activateSettings -u so trackpad changes apply without a logout"
    drop_trackpad_logout
    return 0
  fi
  if "$bin" -u; then
    say_ok "activateSettings -u — trackpad changes apply without a logout"
    drop_trackpad_logout
  else
    WARNINGS=$((WARNINGS + 1))
    say_warn "activateSettings -u failed — trackpad changes need a logout to apply"
  fi
}
drop_trackpad_logout() {
  local item kept=""
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    case "$item" in
      trackpad\|*) ;;
      *) kept="${kept}${kept:+$NL}${item}" ;;
    esac
  done <<< "$LOGOUT_ITEMS"
  LOGOUT_ITEMS="$kept"
  if [ -z "$LOGOUT_ITEMS" ]; then
    NEEDS_LOGOUT=0
  fi
}
activate_trackpad_settings

# ---- dictation hotkey 164 (nested symbolichotkeys; not a macos-defaults row) ----
# Pin "Start Dictation" to Right Command twice so hold-Fn never owns the mic.
apply_dictation_hotkey() {
  local pin="$DOTDIR/scripts/pin-dictation-hotkey-164.sh"
  local desired_enabled=1 desired_type=modifier desired_p1=1048592
  local hk blk enabled ptype p1
  CONSIDERED=$((CONSIDERED + 1))
  if [ ! -x "$pin" ]; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "scripts/pin-dictation-hotkey-164.sh missing — skip dictation hotkey"
    return 0
  fi
  hk="$(defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null || true)"
  blk="$(printf '%s\n' "$hk" | awk '
    $0 ~ /^[[:space:]]*164 =/ {grab=1}
    grab {print}
    grab && $0 ~ /^[[:space:]]*};[[:space:]]*$/ {exit}
  ')"
  enabled="$(printf '%s\n' "$blk" | awk '/enabled/ {print $3; exit}' | tr -d ';' )"
  ptype="$(printf '%s\n' "$blk" | awk '/type/ {print $3; exit}' | tr -d '";' )"
  p1="$(printf '%s\n' "$blk" | awk '/parameters/ {getline; print $1; exit}' | tr -d ',' )"
  if [ "$enabled" = "$desired_enabled" ] && [ "$ptype" = "$desired_type" ] && [ "$p1" = "$desired_p1" ]; then
    if [ "$DRY_RUN" = 1 ]; then
      say_ok "dictation hotkey 164 already Right Command twice (dry-run)"
    elif [ -n "$ONLY_IDS" ]; then
      say_ok "dictation hotkey 164 already Right Command twice (left alone)"
    else
      "$pin" >/dev/null
      REASSERTED=$((REASSERTED + 1))
      say_ok "dictation hotkey 164 already Right Command twice (re-asserted)"
    fi
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    CHANGED=$((CHANGED + 1))
    say_chg "dictation hotkey 164 enabled=${enabled:-?} type=${ptype:-?} p1=${p1:-?} -> Right Command twice (dry-run)"
    return 0
  fi
  BACKUP_DOMAINS="$BACKUP_DOMAINS com.apple.symbolichotkeys"
  ensure_backup
  "$pin" >/dev/null
  CHANGED=$((CHANGED + 1))
  say_chg "dictation hotkey 164 enabled=${enabled:-?} type=${ptype:-?} p1=${p1:-?} -> Right Command twice"
  queue_restart logout "Dictation shortcut (symbolic hotkey 164)"
}
if selected @dictation-164; then apply_dictation_hotkey; fi

# ---- Quick Note hotkey 190 (nested symbolichotkeys; not a macos-defaults row) ----
# Disable Globe/Fn+Q so Quick Note never pops open Notes.
apply_quicknote_hotkey() {
  local pin="$DOTDIR/scripts/pin-quicknote-hotkey-190.sh"
  local hk blk enabled ptype p1
  CONSIDERED=$((CONSIDERED + 1))
  if [ ! -x "$pin" ]; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "scripts/pin-quicknote-hotkey-190.sh missing — skip Quick Note hotkey"
    return 0
  fi
  hk="$(defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null || true)"
  blk="$(printf '%s\n' "$hk" | awk '
    $0 ~ /^[[:space:]]*190 =/ {grab=1}
    grab {print}
    grab && $0 ~ /^[[:space:]]*};[[:space:]]*$/ {exit}
  ')"
  enabled="$(printf '%s\n' "$blk" | awk '/enabled/ {print $3; exit}' | tr -d ';' )"
  ptype="$(printf '%s\n' "$blk" | awk '/type/ {print $3; exit}' | tr -d '";' )"
  p1="$(printf '%s\n' "$blk" | awk '/parameters/ {getline; print $1; exit}' | tr -d ',' )"
  case "${enabled:-}" in 0|false|False) en_ok=1 ;; *) en_ok=0 ;; esac
  if [ "$en_ok" = 1 ] && [ "$ptype" = standard ] && [ "$p1" = 65535 ]; then
    if [ "$DRY_RUN" = 1 ]; then
      say_ok "Quick Note hotkey 190 already disabled (dry-run)"
    elif [ -n "$ONLY_IDS" ]; then
      say_ok "Quick Note hotkey 190 already disabled (left alone)"
    else
      "$pin" >/dev/null
      REASSERTED=$((REASSERTED + 1))
      say_ok "Quick Note hotkey 190 already disabled (re-asserted)"
    fi
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    CHANGED=$((CHANGED + 1))
    say_chg "Quick Note hotkey 190 enabled=${enabled:-missing} type=${ptype:-?} p1=${p1:-?} -> disabled (dry-run)"
    return 0
  fi
  BACKUP_DOMAINS="$BACKUP_DOMAINS com.apple.symbolichotkeys"
  ensure_backup
  "$pin" >/dev/null
  CHANGED=$((CHANGED + 1))
  say_chg "Quick Note hotkey 190 enabled=${enabled:-missing} type=${ptype:-?} p1=${p1:-?} -> disabled"
  queue_restart logout "Quick Note shortcut (symbolic hotkey 190)"
}
if selected @quicknote-190; then apply_quicknote_hotkey; fi

# ---- CotEditor theme + monospaced font (nested prefs via export/import) ----
apply_coteditor() {
  local domain=com.coteditor.CotEditor
  local theme="Anura (Dark)"
  local cur_theme cur_font tmp
  CONSIDERED=$((CONSIDERED + 1))
  cur_theme="$(defaults read "$domain" defaultTheme 2>/dev/null || true)"
  cur_font="$(defaults export "$domain" - 2>/dev/null | plutil -extract modes.general.fontType raw - 2>/dev/null || true)"
  if [ "$cur_theme" = "$theme" ] && [ "$cur_font" = "monospaced" ]; then
    if [ "$DRY_RUN" = 1 ]; then
      say_ok "CotEditor theme=$theme fontType=monospaced (dry-run)"
    elif [ -n "$ONLY_IDS" ]; then
      say_ok "CotEditor theme=$theme fontType=monospaced (left alone)"
    else
      defaults write "$domain" defaultTheme -string "$theme"
      REASSERTED=$((REASSERTED + 1))
      say_ok "CotEditor theme=$theme fontType=monospaced (re-asserted)"
    fi
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    CHANGED=$((CHANGED + 1))
    say_chg "CotEditor theme=${cur_theme:-unset} fontType=${cur_font:-unset} -> theme=$theme fontType=monospaced (dry-run)"
    return 0
  fi
  BACKUP_DOMAINS="$BACKUP_DOMAINS com.coteditor.CotEditor"
  ensure_backup
  defaults write "$domain" defaultTheme -string "$theme"
  tmp="$(mktemp -t coteditor-prefs)"
  defaults export "$domain" "$tmp"
  if /usr/libexec/PlistBuddy -c 'Print :modes' "$tmp" >/dev/null 2>&1; then
    :
  else
    /usr/libexec/PlistBuddy -c 'Add :modes dict' "$tmp"
  fi
  if /usr/libexec/PlistBuddy -c 'Print :modes:general' "$tmp" >/dev/null 2>&1; then
    :
  else
    /usr/libexec/PlistBuddy -c 'Add :modes:general dict' "$tmp"
  fi
  if /usr/libexec/PlistBuddy -c 'Print :modes:general:fontType' "$tmp" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c 'Set :modes:general:fontType monospaced' "$tmp"
  else
    /usr/libexec/PlistBuddy -c 'Add :modes:general:fontType string monospaced' "$tmp"
  fi
  defaults import "$domain" "$tmp"
  rm -f "$tmp"
  CHANGED=$((CHANGED + 1))
  say_chg "CotEditor theme=${cur_theme:-unset} fontType=${cur_font:-unset} -> theme=$theme fontType=monospaced"
}
if selected @coteditor; then apply_coteditor; fi

# ---- Finder sidebar Recents hidden (TopSidebarSection SFL) ----
apply_finder_recents() {
  local helper="$DOTDIR/lib/finder-sidebar-recents.py" out rc
  CONSIDERED=$((CONSIDERED + 1))
  if [ ! -r "$helper" ]; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "finder-sidebar-recents.py missing — skip Finder Recents"
    return 0
  fi
  if [ -z "$DOT_PYTHON" ]; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "python3 not found — skip Finder Recents"
    return 0
  fi
  # Guard exit status: with set -e, a failing $(...) aborts before rc= is set.
  out="$("$DOT_PYTHON" "$helper" 2>&1)" && rc=0 || rc=$?
  if [ "$rc" = 3 ] || printf '%s\n' "$out" | rg -q 'tcc=denied|Operation not permitted|PermissionError'; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "Finder Recents unreadable (Full Disk Access) — enable this terminal in System Settings → Privacy & Security → Full Disk Access"
    return 0
  fi
  if [ "$rc" = 0 ]; then
    if [ "$DRY_RUN" = 1 ]; then
      say_ok "Finder sidebar Recents hidden (dry-run)"
    else
      REASSERTED=$((REASSERTED + 1))
      say_ok "Finder sidebar Recents already hidden"
    fi
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    CHANGED=$((CHANGED + 1))
    say_chg "Finder sidebar Recents -> hide ($out) (dry-run)"
    return 0
  fi
  if "$DOT_PYTHON" "$helper" --apply >/dev/null; then
    CHANGED=$((CHANGED + 1))
    say_chg "Finder sidebar Recents -> hidden"
    queue_restart Finder
  else
    WARNINGS=$((WARNINGS + 1))
    say_warn "Finder sidebar Recents apply failed ($out)"
  fi
}
if selected @finder-recents; then apply_finder_recents; fi

# ---- Finder icon-view defaults (iconSize=72, textSize=13) ----
apply_finder_icon_view() {
  local pin="$DOTDIR/scripts/pin-finder-icon-view.sh"
  CONSIDERED=$((CONSIDERED + 1))
  if [ ! -x "$pin" ]; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "scripts/pin-finder-icon-view.sh missing — skip Finder icon view defaults"
    return 0
  fi
  if "$pin" --check >/dev/null 2>&1; then
    if [ "$DRY_RUN" = 1 ]; then
      say_ok "Finder icon view defaults iconSize=72 textSize=13 (dry-run)"
    elif [ -n "$ONLY_IDS" ]; then
      say_ok "Finder icon view defaults already iconSize=72 textSize=13 (left alone)"
    else
      "$pin" >/dev/null
      REASSERTED=$((REASSERTED + 1))
      say_ok "Finder icon view defaults already iconSize=72 textSize=13 (re-asserted)"
    fi
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    CHANGED=$((CHANGED + 1))
    say_chg "Finder icon view defaults -> iconSize=72 textSize=13 (dry-run)"
    return 0
  fi
  BACKUP_DOMAINS="$BACKUP_DOMAINS com.apple.finder"
  ensure_backup
  "$pin" >/dev/null
  CHANGED=$((CHANGED + 1))
  say_chg "Finder icon view defaults -> iconSize=72 textSize=13"
  queue_restart Finder
}
if selected @finder-icon-view; then apply_finder_icon_view; fi

# ---- Finder sidebar Favorites (read the sidebar file; never write it) ----
# mysides is not a Homebrew formula or cask, and writing FavoriteItems.sfl4
# is not reliable. A difference is a warning. Finder is not restarted.
apply_finder_favorites() {
  local helper="$DOTDIR/lib/sidebar-favorites.py" list="$DOTDIR/lib/sidebar-favorites.list"
  local verdict status detail
  CONSIDERED=$((CONSIDERED + 1))
  if [ ! -r "$helper" ] || [ ! -r "$list" ]; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "sidebar favorites files missing — skip Finder Favorites"
    return 0
  fi
  if [ -z "$DOT_PYTHON" ]; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "python3 not found — skip Finder Favorites"
    return 0
  fi
  verdict="$("$DOT_PYTHON" "$helper" compare --list "$list" || true)"
  status="${verdict%%|*}"
  detail="${verdict#*|}"
  if [ "$status" = ok ]; then
    say_ok "Finder Favorites already match"
    return 0
  fi
  WARNINGS=$((WARNINGS + 1))
  if [ "$status" = bad ]; then
    say_warn "Finder Favorites differ ($detail). Set them in Finder; this does not change the sidebar"
  else
    say_warn "${detail:-Finder Favorites could not be read}"
  fi
}
if selected @finder-favorites; then apply_finder_favorites; fi

# ---- Show Finder menu shortcut (Cmd-Ctrl-Shift-F) -----------------------
# -dict-add changes this one entry and leaves any other menu shortcuts.
apply_finder_show() {
  local raw val
  CONSIDERED=$((CONSIDERED + 1))
  raw="$(defaults read com.apple.finder NSUserKeyEquivalents 2>/dev/null || true)"
  val="$(finder_show_value "$raw")"
  # '@^$f' is Cmd-Ctrl-Shift-F. The dollar sign is part of the shortcut, not a variable.
  # shellcheck disable=SC2016
  if [ "$val" = '@^$f' ]; then
    if [ "$DRY_RUN" = 1 ]; then
      say_ok "Show Finder shortcut already Cmd-Ctrl-Shift-F (dry-run)"
    elif [ -n "$ONLY_IDS" ]; then
      say_ok "Show Finder shortcut already Cmd-Ctrl-Shift-F (left alone)"
    else
      # shellcheck disable=SC2016
      defaults write com.apple.finder NSUserKeyEquivalents -dict-add 'Show Finder' -string '@^$f'
      REASSERTED=$((REASSERTED + 1))
      say_ok "Show Finder shortcut already Cmd-Ctrl-Shift-F (re-asserted)"
    fi
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    CHANGED=$((CHANGED + 1))
    say_chg "Show Finder shortcut ${val:-unset} -> Cmd-Ctrl-Shift-F (dry-run)"
    return 0
  fi
  BACKUP_DOMAINS="$BACKUP_DOMAINS com.apple.finder"
  ensure_backup
  # shellcheck disable=SC2016
  defaults write com.apple.finder NSUserKeyEquivalents -dict-add 'Show Finder' -string '@^$f'
  CHANGED=$((CHANGED + 1))
  say_chg "Show Finder shortcut ${val:-unset} -> Cmd-Ctrl-Shift-F"
  queue_restart Finder
}
if selected @finder-show; then apply_finder_show; fi

# ---- Drop the old double-click-minimizes key if it is set ----------------
# AppleActionOnDoubleClick=Fill is a normal defaults row. This only deletes
# AppleMiniaturizeOnDoubleClick when that older key is present, so a double-click
# fills the window instead of minimizing it. Unset is left alone.
apply_titlebar_double_click() {
  local cur
  CONSIDERED=$((CONSIDERED + 1))
  if ! cur="$(defaults read NSGlobalDomain AppleMiniaturizeOnDoubleClick 2>/dev/null)"; then
    say_ok "AppleMiniaturizeOnDoubleClick is unset (double-click fills the window)"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    CHANGED=$((CHANGED + 1))
    say_chg "AppleMiniaturizeOnDoubleClick=${cur} -> delete (dry-run)"
    return 0
  fi
  BACKUP_DOMAINS="$BACKUP_DOMAINS NSGlobalDomain"
  ensure_backup
  if defaults delete NSGlobalDomain AppleMiniaturizeOnDoubleClick; then
    CHANGED=$((CHANGED + 1))
    say_chg "AppleMiniaturizeOnDoubleClick=${cur} -> deleted"
  else
    WARNINGS=$((WARNINGS + 1))
    say_warn "could not delete AppleMiniaturizeOnDoubleClick"
  fi
}
if selected @titlebar-double-click; then apply_titlebar_double_click; fi

# ---- Power (sudo pmset; skipped when sudo is not available) --------------
# lib/ac-sleep.py reads the same pmset -g custom text as the check. sudo runs
# only the commands that are still wrong (AC sleep 0, AC display sleep 10,
# battery display sleep 2, AC wake for network access). Skipped when sudo
# isn't available or isn't wanted. Battery idle sleep is not changed.
# Closing the lid still sleeps the Mac. --fix never selects @ac-sleep.
apply_ac_sleep() {
  local helper="$DOTDIR/lib/ac-sleep.py" custom line rest cmds msg shown reply c failed
  CONSIDERED=$((CONSIDERED + 1))
  if ! command -v pmset >/dev/null 2>&1; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "pmset missing — skipped power settings (manual step ac-sleep)"
    return 0
  fi
  if [ ! -r "$helper" ] || [ -z "$DOT_PYTHON" ]; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "can't read power settings — skipped (manual step ac-sleep)"
    return 0
  fi
  custom="$(pmset -g custom 2>/dev/null || true)"
  if [ -z "$custom" ]; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "pmset -g custom returned nothing — skipped power settings (manual step ac-sleep)"
    return 0
  fi
  line="$(printf '%s\n' "$custom" | "$DOT_PYTHON" "$helper" || true)"
  rest="${line#*|}"
  cmds="${rest%%|*}"
  msg="${rest#*|}"
  shown="$(printf '%s\n' "$cmds" | awk -F';' '{
    out = ""
    for (i = 1; i <= NF; i++) {
      if ($i == "") continue
      if (out != "") out = out "; "
      out = out "sudo " $i
    }
    print out
  }')"
  if [ "${line%%|*}" = ok ]; then
    say_ok "$msg"
    return 0
  fi
  if [ "${line%%|*}" != bad ] || [ -z "$cmds" ]; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "${msg:-cannot read power settings — skipped (manual step ac-sleep)}"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    CHANGED=$((CHANGED + 1))
    say_chg "power settings (dry-run: $shown)"
    return 0
  fi
  # Passwordless sudo can run with no prompt. Otherwise a terminal is asked;
  # no terminal means sudo isn't available (don't hang waiting for a password).
  if ! sudo -n true 2>/dev/null; then
    if [ ! -t 0 ] || [ ! -t 1 ]; then
      WARNINGS=$((WARNINGS + 1))
      say_warn "sudo not available — skipped power settings (manual step ac-sleep: $shown)"
      return 0
    fi
    if [ "$YES" != 1 ]; then
      printf '  Set sleep, display sleep, and wake for network access? Runs: %s  [y/N]\n' "$shown"
      read -r reply || reply=''
      case "$reply" in
        y|Y|yes|YES) ;;
        *)
          WARNINGS=$((WARNINGS + 1))
          say_warn "skipped power settings — sudo not wanted (manual step ac-sleep)"
          return 0
          ;;
      esac
    fi
  fi
  failed=0
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    # shellcheck disable=SC2086  # c is one pmset command; the words are its arguments
    if sudo $c; then
      :
    else
      failed=1
      WARNINGS=$((WARNINGS + 1))
      say_warn "sudo $c failed — manual step ac-sleep"
      break
    fi
  done <<EOF
$(printf '%s' "$cmds" | tr ';' '\n')
EOF
  if [ "$failed" = 0 ]; then
    CHANGED=$((CHANGED + 1))
    say_chg "power settings applied ($shown)"
  fi
}
if selected @ac-sleep; then apply_ac_sleep; fi

# ---- Built-in display More Space (displayplacer) -------------------------
# Only the built-in panel, and only when it is not already More Space.
# External screens are repeated with their current mode so they stay put.
# A missing displayplacer, or no matching scaled mode, stays the manual step.
apply_display_more_space() {
  local helper="$DOTDIR/lib/display-resolution.py"
  local list="$DOTDIR/lib/display-resolution.list"
  local json line status msg plan first rest cfg placer_file
  local -a args
  CONSIDERED=$((CONSIDERED + 1))
  if ! command -v system_profiler >/dev/null 2>&1; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "built-in display: system_profiler is not available — set More Space by hand (System Settings → Displays)"
    return 0
  fi
  if [ -z "$DOT_PYTHON" ] || [ ! -r "$helper" ] || [ ! -r "$list" ]; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "built-in display: display resolution files missing — set More Space by hand (System Settings → Displays)"
    return 0
  fi
  if ! json="$(system_profiler SPDisplaysDataType -json </dev/null 2>/dev/null)"; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "built-in display: system_profiler failed — set More Space by hand (System Settings → Displays)"
    return 0
  fi
  if [ -z "$json" ]; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "built-in display: system_profiler returned nothing — set More Space by hand (System Settings → Displays)"
    return 0
  fi
  line="$(printf '%s\n' "$json" | "$DOT_PYTHON" "$helper" --list "$list" || true)"
  status="${line%%|*}"
  msg="${line#*|*|}"
  case "$status" in
    ok)
      say_ok "built-in display already More Space"
      return 0
      ;;
    info)
      say_ok "$msg"
      return 0
      ;;
    warn)
      ;;
    *)
      WARNINGS=$((WARNINGS + 1))
      say_warn "built-in display: ${msg:-could not read the display report}. Set More Space by hand (System Settings → Displays)"
      return 0
      ;;
  esac
  if ! command -v displayplacer >/dev/null 2>&1; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "built-in display: displayplacer is not installed — set More Space by hand (System Settings → Displays). Run brewsync to install it."
    return 0
  fi
  placer_file="$(mktemp)"
  displayplacer list >"$placer_file" 2>/dev/null || true
  plan="$(printf '%s\n' "$json" | "$DOT_PYTHON" "$helper" --list "$list" --plan --placer "$placer_file" || true)"
  rm -f "$placer_file"
  first="${plan%%$'\n'*}"
  status="${first%%|*}"
  msg="${first#*|*|}"
  args=()
  if [ "$status" = apply ]; then
    rest="${plan#*$'\n'}"
    if [ "$rest" != "$plan" ]; then
      while IFS= read -r cfg; do
        case "$cfg" in
          screen\|*) args+=("${cfg#screen|}") ;;
        esac
      done <<< "$rest"
    fi
  fi
  if [ "$status" != apply ] || [ "${#args[@]}" -eq 0 ]; then
    WARNINGS=$((WARNINGS + 1))
    say_warn "${msg:-built-in display: could not choose a More Space mode — set it by hand (System Settings → Displays)}"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    CHANGED=$((CHANGED + 1))
    say_chg "built-in display would be set to More Space (${msg})"
    return 0
  fi
  if displayplacer "${args[@]}"; then
    CHANGED=$((CHANGED + 1))
    say_chg "built-in display set to More Space (${msg})"
  else
    WARNINGS=$((WARNINGS + 1))
    say_warn "built-in display: displayplacer failed — set More Space by hand (System Settings → Displays)"
  fi
}
if selected @display-more-space; then apply_display_more_space; fi

# --only ids that matched nothing (typo, or a row removed from the list).
if [ -n "$ONLY_IDS" ]; then
  while IFS= read -r oid; do
    [ -n "$oid" ] || continue
    case "$NL$ONLY_MATCHED$NL" in
      *"$NL$oid$NL"*) : ;;
      *) WARNINGS=$((WARNINGS + 1)); say_warn "--only $oid matched nothing in lib/macos-defaults.list or the @ items" ;;
    esac
  done <<< "$ONLY_IDS"
fi

echo
echo "Summary: $CONSIDERED setting(s) checked, $CHANGED changed, $REASSERTED re-asserted, $WARNINGS warning(s)."

# ---- deferred UI restarts (only if something changed) -------------------
if [ "$DRY_RUN" != 1 ] && [ "$CHANGED" -gt 0 ] && [ -n "${RESTARTS// /}" ]; then
  echo
  if [ "$YES" = 1 ]; then
    reply=y
    printf 'Restarting to apply:%s\n' "$RESTARTS"
  else
    printf 'Restart now to apply:%s ? [y/N] ' "$RESTARTS"
    read -r reply || reply=''
  fi
  case "$reply" in
    y|Y|yes|YES)
      # shellcheck disable=SC2086  # intentional: $RESTARTS is a space-separated list we want word-split
      for p in $RESTARTS; do
        if killall "$p" 2>/dev/null; then echo "  restarted $p"; else echo "  $p not running"; fi
      done ;;
    *) echo '  skipped — changes apply at next login.' ;;
  esac
fi

if [ "$NEEDS_LOGOUT" = 1 ] && [ "$CHANGED" -gt 0 ]; then
  echo
  echo 'Note: the following changed and may need a logout/login to fully apply:'
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    label="${item#*|}"
    printf '  - %s\n' "$label"
    if [ "$DRY_RUN" != 1 ]; then
      dotfiles_note_logout "$label"
    fi
  done <<< "$LOGOUT_ITEMS"
fi

if [ -n "$ONLY_IDS" ]; then exit 0; fi   # --only (macconfig-check.sh --fix): skip the manual-steps footer

cat <<'MANUAL'

Still manual (not scriptable / out of scope) — see docs/manual-steps.md:
  - The account picture (the Dog) is checked and never changed
  - Keyboard British input source (checked; not written). Built-in display
    More Space is set with displayplacer when that mode is listed; otherwise
    set it by hand. The Tahoe Night wallpaper stays by hand (there is no
    reliable command for that system picture). Automatically adjust
    brightness stays by hand (System Settings → Displays)
  - Finder sidebar Favorites are checked from the sidebar file and not changed.
    macconfig checks the Tags group collapsed, Recents hidden, and, when the
    sidebar files name the row, Shared at the top, AirDrop and iCloud Drive
    hidden, and your home folder, Macintosh HD, Network, and Trash visible.
    A row the files do not name stays manual. macconfig does not change the sidebar
  - Mouse double-click speed and secondary click (tracking 1.5 and scrolling 0.5
    are checked only — defaults write is unreliable, so they are never written);
    Trackpad Look up (checked, forceClick 0) and trackpad dragging (checked
    only, Dragging=1 DragLock=0); MX Master 3S wheel (Natural), buttons in Logi
    Options+ (checked by macconfig-check.sh, never written); Logi cloud backup
  - Accessibility grants (TCC); notification mirroring. Spotlight → Results from
    Apps is check by hand (the toggles are not in a preference the check can
    read). Per-app Allow Notifications is checked
  - Menu Bar → Allow in the Menu Bar: Raycast, Logi Options+ and Docker Off
    (leave Tailscale, 1Password, Granola, Hammerspoon, Fleet Desktop)
  - Set Hostname (requires sudo)
  - Power, if the sudo step above was skipped: AC sleep 0, AC display sleep
    10 minutes, battery display sleep 2 minutes, AC wake for network access.
    Closing the lid still sleeps the Mac. Battery idle sleep is not changed
MANUAL
