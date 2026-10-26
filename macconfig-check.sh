#!/usr/bin/env bash
#
# macconfig-check.sh — verifier. By default read-only: reports drift between this machine and the
# repo's desired state WITHOUT changing anything. Exits non-zero if any drift is found, so
# it's usable in a pre-push hook or CI later. A missing company app is a warning, not drift.
# In a terminal the MDM section offers to open Fleet Self service. That does not install
# the app, and --fix does not either. With --fix it also applies the SAFE fixes
# from lib/autofix.list (reversible preference writes via the existing setters), re-checks,
# and prints a "Fixed" and a "Needs Paul" list.
#
# Sections: symlinks, Homebrew (Brewfile + cleanup extras), macOS defaults, Dock, Dock desktop assignments, login shell, hostname, display auto-brightness, built-in display More Space, AC idle sleep (pmset -g custom, AC Power sleep only), URL handlers, Finder file handlers, unwanted apps, dictation shortcut + Quick Note shortcut + Spotlight shortcut (Command+Space, no LaunchAgent) + login LaunchAgents, Finder icon view defaults, Karabiner Fn-kill + Finder Trash + hidden menu bar icon, Hammerspoon (running), login items guard, Finder Recents, CotEditor, Ghostty config (valid, not overridden, effective = repo), Logi Options+ (MX Master 3S wheel / thumb wheel / gesture button / pointer speed vs lib/logi-expected.list, from a temp copy of settings.db), Modes (hammerspoon/modes.lua valid, Focus Shortcuts + Focus modes exist, current mode not left on > HEALTH_MODE_MAX_HOURS), Notifications (per-app Allow Notifications vs lib/notifications-off.list, Hammerspoon alert style, read-only usernoted plist), MDM apps, leftover *.app.back, security hygiene (FileVault, firewall stealth, automatic updates, pending-update age from the local plist, SSH; commit signing only when it is on), account picture (the Dog), placed desktop widgets (notificationcenterui widgets.instances, read-only), Karabiner background items, Finder sidebar rows the sidebar files name, Mac health (battery, disk, uptime, memory, storage hogs, security basics, MDM, crashes, background jobs, dotfiles sync, unexpected login items), manual steps (scripts/manual-steps.sh check: permissions, sign-ins, British input, GitHub CLI, 1Password CLI, pointer size, by-hand settings).
# Reuses lib/macos-defaults.list, lib/dock-apps.list, lib/desktop-bindings.list, lib/file-handlers.list, lib/hostname, lib/notification-prefs.py, lib/display-resolution.py, lib/display-resolution.list, lib/ac-sleep.py and lib/defaults-lib.sh
# so the verify path uses the exact same data and comparison semantics as the apply path
# (macos.sh / dock.sh / lib/desktop-bindings.py / lib/file-handlers.py) and the two can never drift.
#
# Each section is a checks/<area>.sh file sourced below, in this order, so the
# report, the summary, and the exit status stay the same. --only runs a subset.
#
# Flags:
#   --no-color     Disable ANSI colour (also honours the NO_COLOR env var).
#   --health-json  Print only a JSON summary (Mac health values, drift/warning counts and
#                  messages) on stdout, for the weekly health note. Same checks, same exit.
#                  attention[] repeats the short "needs attention" bullets. With --fix it
#                  also has fixed[] / needs_paul[] (and would_fix[] on a dry run).
#   --fix          After the checks, apply the SAFE fixes (lib/autofix.list) for any drift or
#                  warning found, re-run the checks, and report Fixed / Needs Paul. Every fix
#                  is idempotent and logged to ~/Library/Logs/com.pdone.check-fix.log.
#                  Exit status then reflects the drift left AFTER the fixes.
#   --dry-run      With --fix: show what would be fixed; change nothing.
#   --issues       Internal (used by --fix to re-check): print one line per drift/warning
#                  (kind, id, arg, message, section; separated by \x1f) on stdout and nothing else.
#   --only AREA[,AREA]
#                  Run only those areas, in the usual order. check.sh and macconfig pass it through.
#   -h, --help     Show usage.
#
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fail early with a clear message if a required data/helper file is missing.
require_file() { [ -r "$1" ] || { echo "Error: required file not found: $1" >&2; exit 1; }; }
for f in defaults-lib.sh links.list macos-defaults.list dock-apps.list hostname; do
  require_file "$DOTDIR/lib/$f"
done

# Hostname is defined once in lib/hostname (shared with hostname.sh).
EXPECTED_HOST="$(awk '$1 !~ /^#/ && NF {print $1; exit}' "$DOTDIR/lib/hostname")"
NO_COLOR_OPT=0
HEALTH_JSON=0
FIX=0
DRY_RUN=0
ISSUES=0

# Area names match checks/<area>.sh. finder is one area with two sections.
KNOWN_AREAS=" symlinks brew mdm defaults dock desktops shell hostname display power handlers files apps hotkeys finder karabiner hammerspoon login-items coteditor ghostty logi modes notifications backups security health manual "
ONLY_RAW=""
ONLY_SET=0
ONLY_NORM=""

area_selected() {
  if [ -z "$ONLY_NORM" ]; then
    return 0
  fi
  case "$ONLY_NORM" in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

normalize_only() {
  local rest="$1" area
  ONLY_NORM=","
  while [ -n "$rest" ]; do
    area="${rest%%,*}"
    if [ "$area" = "$rest" ]; then
      rest=""
    else
      rest="${rest#*,}"
    fi
    area="${area#"${area%%[![:space:]]*}"}"
    area="${area%"${area##*[![:space:]]}"}"
    [ -n "$area" ] || continue
    case "$KNOWN_AREAS" in
      *" $area "*) ;;
      *)
        echo "Unknown area: $area" >&2
        echo "Areas:${KNOWN_AREAS}" >&2
        exit 2
        ;;
    esac
    case "$ONLY_NORM" in
      *",$area,"*) ;;
      *) ONLY_NORM="${ONLY_NORM}${area}," ;;
    esac
  done
  if [ "$ONLY_NORM" = "," ]; then
    echo "--only needs at least one area (for example: --only dock,power)" >&2
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no-color) NO_COLOR_OPT=1; shift ;;
    --health-json) HEALTH_JSON=1; shift ;;
    --fix) FIX=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --issues) ISSUES=1; shift ;;
    --only)
      if [ $# -lt 2 ] || [ "${2#--}" != "$2" ]; then
        echo "--only needs an area list, for example: --only dock,power (try --help)" >&2
        exit 2
      fi
      ONLY_SET=1
      ONLY_RAW="${ONLY_RAW:+$ONLY_RAW,}$2"
      shift 2
      ;;
    --only=*)
      ONLY_SET=1
      ONLY_RAW="${ONLY_RAW:+$ONLY_RAW,}${1#--only=}"
      shift
      ;;
    -h|--help)
      cat <<EOF
Usage: macconfig-check.sh [--no-color] [--health-json] [--fix [--dry-run]] [--only AREA[,AREA]]
  Default: read-only. Reports drift between this machine and the repo; writes nothing.
  Exit status: 0 = everything matches, 1 = drift found.
  --no-color     Disable ANSI colour (also honours the NO_COLOR env var).
  --health-json  Print only a JSON summary on stdout (Mac health values, drift and
                 warning counts and messages, plus attention[]) for the weekly health note.
                 With --fix it also carries fixed[] and needs_paul[] (would_fix[] on a dry run).
  --fix          Apply the SAFE fixes from lib/autofix.list for the drift found (reversible
                 preference writes only), re-check, and print Fixed / Needs Paul lists.
                 Exit status reflects the drift left after the fixes. A missing company
                 app stays a warning. In a terminal the check offers to open Fleet
                 Self service first. --fix does not install it.
  --dry-run      With --fix: show what would be fixed; change nothing.
  --only AREA[,AREA]
                 Run only these areas, in the usual order (not the order you type).
                 Areas:${KNOWN_AREAS}
                 finder is both Finder sections. Repeat --only to add areas.
                 check.sh and the macconfig fish function pass this flag through.
  -h, --help     Show this help.
EOF
      exit 0 ;;
    *) echo "Unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done
if [ "$ONLY_SET" = 1 ]; then
  normalize_only "$ONLY_RAW"
fi
if [ "$DRY_RUN" = 1 ] && [ "$FIX" != 1 ]; then
  echo "--dry-run only applies to --fix (macconfig-check.sh is read-only without --fix)" >&2; exit 2
fi
if [ "$ISSUES" = 1 ]; then
  if [ "$FIX" = 1 ] || [ "$HEALTH_JSON" = 1 ]; then
    echo "--issues is internal and can't be combined with --fix or --health-json" >&2; exit 2
  fi
fi

# --health-json / --issues: keep the machine output alone on stdout (fd 3); the human
# report goes nowhere.
if [ "$HEALTH_JSON" = 1 ] || [ "$ISSUES" = 1 ]; then
  exec 3>&1 1>/dev/null
  NO_COLOR_OPT=1
fi

# ---- logging (colour only on a tty) -------------------------------------
if [ -t 1 ] && [ "$NO_COLOR_OPT" != 1 ] && [ -z "${NO_COLOR+x}" ]; then
  C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_WARN=$'\033[33m'; C_HDR=$'\033[1m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_OK=''; C_BAD=''; C_WARN=''; C_HDR=''; C_DIM=''; C_OFF=''
fi

CHECKED=0; OKS=0; DRIFT=0; WARN=0; HAND=0
DRIFT_MSGS=(); WARN_MSGS=()   # kept for --health-json
# Every drift / warning is tagged with an issue id from lib/autofix.list (set by `fixid`
# before the check; `hdr` resets it) so --fix knows which ones are SAFE to repair.
US=$'\037'                    # field separator for FIX_ITEMS / --issues / attention items
FIX_ID=unclassified; FIX_ARG=''
FIX_ITEMS=()                  # "kind US id US arg US message" per drift / warning
SECTION=""
# "kind US section US id US message" — collected in bad/warn, in check order. By-hand
# info lines never land here. RECHECK_* is the same shape for what's still outstanding
# after a real --fix re-check. ATTN_LINES is the plain bullet text (summary + JSON).
ATTN_ITEMS=(); RECHECK_ITEMS=(); RECHECK_RAN=0; ATTN_LINES=()
fixid() { FIX_ID="$1"; FIX_ARG="${2:-}"; }   # fixid ID [ARG] — tag the following lines
record() { FIX_ITEMS+=("$1$US$FIX_ID$US$FIX_ARG$US${2//$US/ }"); }
attn_push() { # kind message — alongside record, from bad/warn only
  local msg="${2//$US/ }"
  msg="${msg//$'\n'/ }"
  ATTN_ITEMS+=("$1$US$SECTION$US$FIX_ID$US$msg")
}
pass() { OKS=$((OKS + 1));    printf '  %sok%s    %s\n'  "$C_OK"   "$C_OFF" "$1"; }
bad()  { DRIFT=$((DRIFT + 1)); DRIFT_MSGS+=("$1"); record drift "$1"; attn_push drift "$1"; printf '  %sDRIFT%s %s\n' "$C_BAD"  "$C_OFF" "$1"; }
warn() { WARN=$((WARN + 1));   WARN_MSGS+=("$1");  record warn "$1";  attn_push warn "$1";  printf '  %swarn%s  %s\n'  "$C_WARN" "$C_OFF" "$1"; }
info() { HAND=$((HAND + 1));   printf '  info  %s\n' "$1"; }   # check-by-hand item: not drift, not a warning
note() { printf '  info  %s\n' "$1"; }                         # FYI line: not counted anywhere
# Same printed line as info. manualsteps treats skip as "does not apply"
# (a clamshell display, an unlisted panel) and does not walk that step.
skip() { info "$1"; }

# with_timeout SECS CMD... — macOS has no timeout(1) by default; perl's alarm survives
# exec, so CMD is killed (status 142) if it runs longer than SECS.
with_timeout() {
  local secs="$1"; shift
  perl -e '$t = shift @ARGV; alarm $t; exec { $ARGV[0] } @ARGV or exit 127' "$secs" "$@"
}
hdr()  { SECTION="$1"; fixid unclassified; printf '\n%s%s%s\n' "$C_HDR" "$1" "$C_OFF"; }

# Value-comparison helpers shared with macos.sh (same semantics, single source).
# shellcheck source=lib/defaults-lib.sh disable=SC1091
. "$DOTDIR/lib/defaults-lib.sh"
DOT_PYTHON="$(dot_python || true)"

# Defaults for --health-json when a section is skipped by --only. The health
# and Hammerspoon sections overwrite the values they measure.
H_BAT_STATUS=none; H_BAT_COND=""; H_BAT_MAX=""; H_BAT_CYCLES=""
H_DISK_STATUS=unknown; H_DISK_FREE_GB=""; H_DISK_FREE_PCT=""; H_DISK_TOTAL_GB=""
H_UP_STATUS=unknown; H_UP_DAYS=""
H_MEM_STATUS=unknown; H_MEM_PRESSURE=unknown; H_MEM_FREE_PCT=""; H_MEM_SWAP_GB=""
H_STO_STATUS=ok; H_STO_CACHES=""; H_STO_DOCKER=""; H_STO_BREW=""; H_STO_DERIVED=""
H_SEC_STATUS=ok; H_SEC_FIREWALL=unknown; H_SEC_GATEKEEPER=unknown; H_SEC_SIP=unknown
H_SEC_SSH=unknown; H_SEC_SCREENSHARING=unknown; H_SEC_FILESHARING=unknown; H_SEC_SCREENLOCK=unknown
H_MDM_STATUS=unknown; H_MDM_ENROLLED=unknown; H_MDM_AGENT=unknown
H_CR_STATUS=unknown; H_CR_PANICS=""; H_CR_CRASHES=""; H_CR_FAULTS=""; H_CR_APPS=(); H_CR_PANIC_FILES=()
HEALTH_CRASH_DAYS=7
H_JOBS_STATUS=ok; H_JOBS=()
H_HS_RUNNING=unknown
H_GIT_STATUS=unknown; H_GIT_DIRTY=""; H_GIT_AHEAD=""; H_GIT_BEHIND=""; H_GIT_FETCHED=""
H_LI_STATUS=unknown; H_LI_ENABLED=0; H_LI_ALLOW=0; H_LI_MDM=0; H_LI_UNKNOWN=(); H_LI_STALE=()
BTM_HELPER="$DOTDIR/lib/btm-login-items.py"
LAUNCHAGENT_CHECKED=""
MANAGED_LINKS=""

# ---- sections (checks/<area>.sh), in report order -----------------------
# Sourced in this shell. A failing command still stops the run.
# Tests source a section with this set so they can call its functions without
# running the section. A normal run always clears it.
unset MACCONFIG_CHECKS_DEFINE_ONLY
if area_selected symlinks; then
  # shellcheck source=checks/symlinks.sh
  . "$DOTDIR/checks/symlinks.sh"
fi

if area_selected brew; then
  # shellcheck source=checks/brew.sh
  . "$DOTDIR/checks/brew.sh"
fi

if area_selected mdm; then
  # shellcheck source=checks/mdm.sh
  . "$DOTDIR/checks/mdm.sh"
fi

if area_selected defaults; then
  # shellcheck source=checks/defaults.sh
  . "$DOTDIR/checks/defaults.sh"
fi

if area_selected dock; then
  # shellcheck source=checks/dock.sh
  . "$DOTDIR/checks/dock.sh"
fi

if area_selected desktops; then
  # shellcheck source=checks/desktops.sh
  . "$DOTDIR/checks/desktops.sh"
fi

if area_selected shell; then
  # shellcheck source=checks/shell.sh
  . "$DOTDIR/checks/shell.sh"
fi

if area_selected hostname; then
  # shellcheck source=checks/hostname.sh
  . "$DOTDIR/checks/hostname.sh"
fi

if area_selected display; then
  # shellcheck source=checks/display.sh
  . "$DOTDIR/checks/display.sh"
fi

if area_selected power; then
  # shellcheck source=checks/power.sh
  . "$DOTDIR/checks/power.sh"
fi

if area_selected handlers; then
  # shellcheck source=checks/handlers.sh
  . "$DOTDIR/checks/handlers.sh"
fi

if area_selected files; then
  # shellcheck source=checks/files.sh
  . "$DOTDIR/checks/files.sh"
fi

if area_selected apps; then
  # shellcheck source=checks/apps.sh
  . "$DOTDIR/checks/apps.sh"
fi

if area_selected hotkeys; then
  # shellcheck source=checks/hotkeys.sh
  . "$DOTDIR/checks/hotkeys.sh"
fi

if area_selected finder; then
  CHECK_PART=icon
  # shellcheck source=checks/finder.sh
  . "$DOTDIR/checks/finder.sh"
  unset CHECK_PART
fi

if area_selected karabiner; then
  # shellcheck source=checks/karabiner.sh
  . "$DOTDIR/checks/karabiner.sh"
fi

if area_selected hammerspoon; then
  # shellcheck source=checks/hammerspoon.sh
  . "$DOTDIR/checks/hammerspoon.sh"
fi

if area_selected login-items; then
  # shellcheck source=checks/login-items.sh
  . "$DOTDIR/checks/login-items.sh"
fi

if area_selected finder; then
  CHECK_PART=recents
  # shellcheck source=checks/finder.sh
  . "$DOTDIR/checks/finder.sh"
  unset CHECK_PART
fi

if area_selected coteditor; then
  # shellcheck source=checks/coteditor.sh
  . "$DOTDIR/checks/coteditor.sh"
fi

if area_selected ghostty; then
  # shellcheck source=checks/ghostty.sh
  . "$DOTDIR/checks/ghostty.sh"
fi

if area_selected logi; then
  # shellcheck source=checks/logi.sh
  . "$DOTDIR/checks/logi.sh"
fi

if area_selected modes; then
  # shellcheck source=checks/modes.sh
  . "$DOTDIR/checks/modes.sh"
fi

if area_selected notifications; then
  # shellcheck source=checks/notifications.sh
  . "$DOTDIR/checks/notifications.sh"
fi

if area_selected backups; then
  # shellcheck source=checks/backups.sh
  . "$DOTDIR/checks/backups.sh"
fi

if area_selected security; then
  # shellcheck source=checks/security.sh
  . "$DOTDIR/checks/security.sh"
fi

if area_selected health; then
  # shellcheck source=checks/health.sh
  . "$DOTDIR/checks/health.sh"
fi

if area_selected manual; then
  # shellcheck source=checks/manual.sh
  . "$DOTDIR/checks/manual.sh"
fi


# ---- --fix: apply the SAFE fixes, re-check, report ------------------------
# lib/autofix.list is the one place that says what's SAFE (reversible preference writes,
# done by the existing setters) and what Needs Paul (report only). Nothing here uses sudo,
# deletes files, or touches apps, login items, permissions, MDM or git.
FIXED=(); NEEDS_PAUL=(); WOULD_FIX=(); LOGOUT_NEEDED=()
AFTER_DRIFT="$DRIFT"; AFTER_WARN="$WARN"
if [ "$FIX" = 1 ]; then
  require_file "$DOTDIR/lib/autofix.list"
  require_file "$DOTDIR/lib/autofix-lib.sh"
  # shellcheck source=lib/autofix-lib.sh disable=SC1091
  . "$DOTDIR/lib/autofix-lib.sh"
  AUTOFIX_LIST="$DOTDIR/lib/autofix.list"
  FIX_LOG="$HOME/Library/Logs/com.pdone.check-fix.log"
  fix_log() {
    mkdir -p "$(dirname "$FIX_LOG")"
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$FIX_LOG"
  }
  if [ "$DRY_RUN" = 1 ]; then
    hdr "Fix — dry run (nothing is changed)"
  else
    hdr "Fix (SAFE fixes from lib/autofix.list)"
    fix_log "macconfig-check.sh --fix started ($DRIFT drift, $WARN warning(s))"
  fi

  # Fixers. Each prints one line saying what it did (or would do) and returns 0 = done /
  # would do, 1 = tried and failed, 2 = refused as unsafe right now. All idempotent.
  fix_symlink() {  # "target|repo-source"
    local target="${1%%|*}" src="${1#*|}"
    if [ ! -e "$src" ]; then
      echo "repo source ${src/#$HOME/~} is missing — restore it from git"; return 2
    fi
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      echo "a real file is in the way at ${target/#$HOME/~} — never overwritten; move it aside, then run install.sh (it backs real files up)"; return 2
    fi
    if [ "$DRY_RUN" = 1 ]; then echo "would link ${target/#$HOME/~} -> repo"; return 0; fi
    if mkdir -p "$(dirname "$target")" && ln -sfn "$src" "$target"; then
      echo "linked ${target/#$HOME/~} -> repo"; return 0
    fi
    echo "ln -sfn failed for ${target/#$HOME/~}"; return 1
  }
  fix_launchagent() {  # "label|plist"
    local label="${1%%|*}" plist="${1#*|}" out wrote=0 src
    src="$DOTDIR/launchagents/${label}.plist"
    if [ "$DRY_RUN" = 1 ]; then
      if [ -f "$src" ] && ! "$DOTDIR/scripts/install-launchagent.sh" --check "$label" >/dev/null 2>&1; then
        echo "would rewrite LaunchAgent $label from repo and reload (bootout/bootstrap)"
      else
        echo "would load LaunchAgent $label (scripts/load-launchagent.sh)"
      fi
      return 0
    fi
    # Rewrite first, then reload, so bootstrap reads the new WatchPaths.
    # A matching plist is left untouched; the job is bootstrapped only if
    # it isn't already loaded (no bootout).
    if [ -f "$src" ]; then
      if ! out="$("$DOTDIR/scripts/install-launchagent.sh" --write "$label")"; then
        echo "LaunchAgent $label: ${out:-render failed}"; return 1
      fi
      case "$out" in
        updated) wrote=1 ;;
        unchanged) ;;
        *) echo "LaunchAgent $label: unexpected render result ($out)"; return 1 ;;
      esac
    fi
    if [ "$wrote" = 1 ]; then
      if out="$("$DOTDIR/scripts/load-launchagent.sh" --reload "$plist" 2>&1)"; then
        echo "LaunchAgent $label reloaded (bootout/bootstrap): $out"; return 0
      fi
      echo "LaunchAgent $label: ${out:-reload failed}"; return 1
    fi
    if out="$("$DOTDIR/scripts/load-launchagent.sh" "$plist" 2>&1)"; then
      echo "LaunchAgent $out"; return 0
    fi
    echo "LaunchAgent $label: ${out:-load failed}"; return 1
  }
  fix_hammerspoon() {
    local i=0
    if [ ! -d /Applications/Hammerspoon.app ]; then
      echo "Hammerspoon.app not installed — run brewsync"; return 2
    fi
    if pgrep -xq Hammerspoon; then echo "Hammerspoon already running"; return 0; fi
    if [ "$DRY_RUN" = 1 ]; then echo "would start Hammerspoon (open -g -a Hammerspoon)"; return 0; fi
    open -g -a Hammerspoon 2>/dev/null || true
    while [ "$i" -lt 15 ] && ! pgrep -xq Hammerspoon; do sleep 1; i=$((i + 1)); done
    if pgrep -xq Hammerspoon; then echo "started Hammerspoon"; return 0; fi
    echo "open -a Hammerspoon didn't start it"; return 1
  }

  # Classify every drift / warning. SAFE items are de-duplicated on id|arg.
  SAFE_ITEMS=()                 # "id US arg US message US fixer"
  MACOS_ARGS=()                 # macos.sh --only … arguments (one batched call)
  DESKTOP_ONLY=""               # bundle ids for one batched desktop-bindings.py --apply
  FILE_ONLY=""                  # extensions for one batched file-handlers.py --apply
  safe_seen="$US"
  for it in ${FIX_ITEMS[@]+"${FIX_ITEMS[@]}"}; do
    IFS="$US" read -r _it_kind it_id it_arg it_msg <<< "$it"
    lookup="$(autofix_lookup "$AUTOFIX_LIST" "$it_id")"
    it_cls="${lookup%%|*}"; it_rest="${lookup#*|}"; it_fixer="${it_rest%%|*}"; it_why="${it_rest#*|}"
    if [ "$it_cls" != SAFE ]; then
      NEEDS_PAUL+=("$it_msg — $it_why")
      continue
    fi
    case "$safe_seen" in *"$US$it_id|$it_arg$US"*) continue ;; esac
    safe_seen="$safe_seen$it_id|$it_arg$US"
    SAFE_ITEMS+=("$it_id$US$it_arg$US$it_msg$US$it_fixer")
    if [ "$it_fixer" = macos ]; then
      if [ "$it_id" = defaults ]; then MACOS_ARGS+=(--only "$it_arg"); else MACOS_ARGS+=(--only "@$it_id"); fi
    elif [ "$it_fixer" = desktop ] && [ -n "$it_arg" ]; then
      DESKTOP_ONLY="${DESKTOP_ONLY:+$DESKTOP_ONLY,}$it_arg"
    elif [ "$it_fixer" = fileext ] && [ -n "$it_arg" ]; then
      FILE_ONLY="${FILE_ONLY:+$FILE_ONLY,}$it_arg"
    fi
  done

  # Run the fixers in dependency order: symlinks, then one batched macos.sh call
  # (one backup, at most one restart per process), then one batched
  # desktop-bindings.py --apply (one backup, one Dock restart), then one batched
  # file-handlers.py --apply (duti -s for each drifted extension), then LaunchAgents
  # (rewrite a drifted plist and bootout/bootstrap, or bootstrap only if it isn't
  # loaded) and Hammerspoon. FIX_RESULTS[n] = "rc US what happened" for SAFE_ITEMS[n].
  FIX_RESULTS=()
  MACOS_OUT=""
  macos_line() {  # id arg — this item's chg / warn / ok line from the macos.sh output
    local pat=""
    case "$1" in
      defaults)         pat="${2%%|*} ${2#*|} —" ;;
      dictation-164)    pat="dictation hotkey 164" ;;
      quicknote-190)    pat="Quick Note hotkey 190" ;;
      spotlight-64)     pat="Spotlight hotkey 64" ;;
      coteditor)        pat="CotEditor" ;;
      finder-recents)   pat="Finder sidebar Recents" ;;
      finder-icon-view) pat="Finder icon view defaults" ;;
      finder-show)      pat="Show Finder shortcut" ;;
      titlebar-double-click) pat="AppleMiniaturizeOnDoubleClick" ;;
      display-more-space) pat="More Space" ;;
      arzopa-display) pat="ARZOPA" ;;
    esac
    printf '%s\n' "$MACOS_OUT" | grep -F -- "$pat" | grep -E '^  (chg|warn|ok) ' | head -1 | sed -E 's/^ +(chg|warn|ok) +//'
  }
  run_fix() {  # fixer arg id — dispatch to the fixer; prints its line, returns its status
    local ml rest
    case "$1" in
      symlink)     fix_symlink "$2" ;;
      launchagent) fix_launchagent "$2" ;;
      hammerspoon) fix_hammerspoon ;;
      desktop)
        ml="$(printf '%s\n' "$DESKTOP_OUT" | awk -F'|' -v b="$2" '$2 == b { print; exit }')"
        if [ -z "$ml" ]; then echo "desktop-bindings.py printed nothing for this item"; return 1; fi
        rest="${ml#*|}"; rest="${rest#*|}"
        echo "desktop: $rest"
        case "${ml%%|*}" in
          chg|ok|dry) return 0 ;;
          refuse) return 2 ;;
          *) return 1 ;;
        esac
        ;;
      fileext)
        ml="$(printf '%s\n' "$FILE_OUT" | awk -F'|' -v e="$2" '$2 == e { print; exit }')"
        if [ -z "$ml" ]; then echo "file-handlers.py printed nothing for this item"; return 1; fi
        rest="${ml#*|}"; rest="${rest#*|}"
        echo "fileext: $rest"
        case "${ml%%|*}" in
          chg|ok|dry) return 0 ;;
          refuse) return 2 ;;
          *) return 1 ;;
        esac
        ;;
      macos)
        ml="$(macos_line "$3" "$2")"
        if [ -z "$ml" ]; then echo "macos.sh printed nothing for this item"; return 1; fi
        echo "macos.sh: $ml"
        if printf '%s\n' "$MACOS_OUT" | grep -F -- "$ml" | grep -q '^  warn '; then return 1; fi ;;
      *) echo "unknown fixer '$1' in lib/autofix.list"; return 2 ;;
    esac
  }
  fix_pass() {  # fixer... — run the SAFE items whose fixer is one of these
    local n=0 item f id arg _msg fixer out rc
    for item in ${SAFE_ITEMS[@]+"${SAFE_ITEMS[@]}"}; do
      IFS="$US" read -r id arg _msg fixer <<< "$item"
      for f in "$@"; do
        if [ "$fixer" = "$f" ]; then
          if out="$(run_fix "$fixer" "$arg" "$id")"; then rc=0; else rc=$?; fi
          FIX_RESULTS[n]="$rc$US$out"
        fi
      done
      n=$((n + 1))
    done
  }
  fix_pass symlink
  if [ "${#MACOS_ARGS[@]}" -gt 0 ]; then
    if [ "$DRY_RUN" = 1 ]; then
      MACOS_OUT="$("$DOTDIR/macos.sh" --dry-run --no-color "${MACOS_ARGS[@]}" 2>&1)" || true
    else
      MACOS_OUT="$("$DOTDIR/macos.sh" --no-color --yes "${MACOS_ARGS[@]}" 2>&1)" || true
      while IFS= read -r ml; do
        if [ -n "$ml" ]; then fix_log "macos.sh: $ml"; fi
      done <<< "$MACOS_OUT"
    fi
    printf '%s\n' "$MACOS_OUT" | sed '/^$/d; s/^/        /'
    # "logout"-class settings: macos.sh lists them after its Note line.
    while IFS= read -r ml; do
      LOGOUT_NEEDED+=("${ml#  - }")
    done < <(printf '%s\n' "$MACOS_OUT" | awk '/^Note: the following changed/ {grab=1; next} grab && /^  - / {print}')
  fi
  # One apply for every drifted bundle: resolve Desktop N → current Space UUID,
  # write app-bindings, restart Dock once. DESKTOP_OUT is status|bundle|message.
  DESKTOP_OUT=""
  if [ -n "$DESKTOP_ONLY" ]; then
    if ! desk_py="$(dot_python)"; then
      while IFS= read -r b; do
        [ -n "$b" ] || continue
        DESKTOP_OUT="${DESKTOP_OUT}fail|${b}|python3 not found — desktop assignment not changed"$'\n'
      done < <(printf '%s\n' "$DESKTOP_ONLY" | tr ',' '\n')
    else
      desk_cmd=("$desk_py" "$DOTDIR/lib/desktop-bindings.py" --apply)
      if [ "$DRY_RUN" = 1 ]; then desk_cmd+=(--dry-run); fi
      desk_cmd+=(--only "$DESKTOP_ONLY" "$DOTDIR/lib/desktop-bindings.list")
      DESKTOP_OUT="$("${desk_cmd[@]}" 2>&1)" || true
      if [ "$DRY_RUN" != 1 ]; then
        while IFS= read -r dl; do
          if [ -n "$dl" ]; then fix_log "desktop: $dl"; fi
        done <<< "$DESKTOP_OUT"
      fi
    fi
    printf '%s\n' "$DESKTOP_OUT" | awk -F'|' 'NF >= 3 && $3 != "" { print "        " $3 }'
  fi
  # One apply for every drifted extension: `duti -s <bundle> .<ext> all`.
  # FILE_OUT is status|ext|message.
  FILE_OUT=""
  if [ -n "$FILE_ONLY" ]; then
    if ! file_py="$(dot_python)"; then
      while IFS= read -r e; do
        [ -n "$e" ] || continue
        FILE_OUT="${FILE_OUT}fail|${e}|python3 not found — file handler not changed"$'\n'
      done < <(printf '%s\n' "$FILE_ONLY" | tr ',' '\n')
    elif ! command -v duti >/dev/null 2>&1; then
      while IFS= read -r e; do
        [ -n "$e" ] || continue
        FILE_OUT="${FILE_OUT}fail|${e}|duti not installed — run brewsync; file handler not changed"$'\n'
      done < <(printf '%s\n' "$FILE_ONLY" | tr ',' '\n')
    else
      file_cmd=("$file_py" "$DOTDIR/lib/file-handlers.py" --apply)
      if [ "$DRY_RUN" = 1 ]; then file_cmd+=(--dry-run); fi
      file_cmd+=(--only "$FILE_ONLY" "$DOTDIR/lib/file-handlers.list")
      FILE_OUT="$("${file_cmd[@]}" 2>&1)" || true
      if [ "$DRY_RUN" != 1 ]; then
        while IFS= read -r fl; do
          if [ -n "$fl" ]; then fix_log "fileext: $fl"; fi
        done <<< "$FILE_OUT"
      fi
    fi
    printf '%s\n' "$FILE_OUT" | awk -F'|' 'NF >= 3 && $3 != "" { print "        " $3 }'
  fi
  fix_pass macos desktop fileext launchagent hammerspoon
  # Items with a fixer name the dispatcher doesn't know (a typo in lib/autofix.list).
  n=0
  for item in ${SAFE_ITEMS[@]+"${SAFE_ITEMS[@]}"}; do
    if [ -z "${FIX_RESULTS[n]:-}" ]; then
      IFS="$US" read -r _id _arg _msg fx <<< "$item"
      FIX_RESULTS[n]="2${US}unknown fixer '$fx' in lib/autofix.list"
    fi
    n=$((n + 1))
  done

  # Report each SAFE item's outcome; on a real run, re-check to see what stuck.
  RECHECK=""
  if [ "$DRY_RUN" != 1 ] && [ "${#SAFE_ITEMS[@]}" -gt 0 ]; then
    recheck_cmd=("$DOTDIR/macconfig-check.sh" --issues)
    if [ -n "${ONLY_NORM:-}" ]; then
      only_arg="${ONLY_NORM#,}"
      only_arg="${only_arg%,}"
      recheck_cmd+=(--only "$only_arg")
    fi
    RECHECK="$("${recheck_cmd[@]}" 2>/dev/null)" || true
    AFTER_DRIFT=0; AFTER_WARN=0
    RECHECK_RAN=1
    RECHECK_ITEMS=()
    # --issues lines are kind, id, arg, message, section. Field 4 stays the message
    # so the "still" match below keeps working; field 5 is the section for the bullets.
    while IFS="$US" read -r rk ri _ra rm rsec; do
      case "$rk" in
        drift) AFTER_DRIFT=$((AFTER_DRIFT + 1)) ;;
        warn)  AFTER_WARN=$((AFTER_WARN + 1)) ;;
        *) continue ;;
      esac
      RECHECK_ITEMS+=("$rk$US${rsec:-}$US$ri$US$rm")
    done <<< "$RECHECK"
  fi
  i=0
  for item in ${SAFE_ITEMS[@]+"${SAFE_ITEMS[@]}"}; do
    IFS="$US" read -r it_id it_arg it_msg it_fixer <<< "$item"
    fr="${FIX_RESULTS[i]}"; fr_rc="${fr%%"$US"*}"; fr_out="${fr#*"$US"}"
    i=$((i + 1))
    if [ "$fr_rc" = 2 ]; then
      NEEDS_PAUL+=("$it_msg — not auto-fixed: $fr_out")
      [ "$DRY_RUN" = 1 ] || fix_log "refused: $it_msg — $fr_out"
      continue
    fi
    if [ "$DRY_RUN" = 1 ]; then
      WOULD_FIX+=("$it_msg → $fr_out")
      continue
    fi
    still="$(printf '%s\n' "$RECHECK" | awk -F"$US" -v id="$it_id" -v arg="$it_arg" '$2 == id && $3 == arg {print $4; exit}')"
    if [ -n "$still" ]; then
      NEEDS_PAUL+=("$it_msg — fix didn't stick (still: $still; $fr_out)")
      fix_log "did not stick: $it_msg — still: $still ($fr_out)"
    elif [ "$fr_rc" = 0 ]; then
      FIXED+=("$it_msg → $fr_out")
      fix_log "fixed: $it_msg → $fr_out"
    else
      NEEDS_PAUL+=("$it_msg — fix failed: $fr_out")
      fix_log "failed: $it_msg — $fr_out"
    fi
  done

  if [ "$DRY_RUN" = 1 ]; then
    printf '\n  Would fix (%d):\n' "${#WOULD_FIX[@]}"
    for x in ${WOULD_FIX[@]+"${WOULD_FIX[@]}"}; do printf '    - %s\n' "$x"; done
    if [ "${#WOULD_FIX[@]}" -eq 0 ]; then printf '    (nothing — no SAFE drift)\n'; fi
  else
    printf '\n  Fixed (%d):\n' "${#FIXED[@]}"
    for x in ${FIXED[@]+"${FIXED[@]}"}; do printf '    - %s\n' "$x"; done
    if [ "${#FIXED[@]}" -eq 0 ]; then printf '    (nothing to fix)\n'; fi
  fi
  printf '\n  Needs Paul (%d):\n' "${#NEEDS_PAUL[@]}"
  for x in ${NEEDS_PAUL[@]+"${NEEDS_PAUL[@]}"}; do printf '    - %s\n' "$x"; done
  if [ "${#NEEDS_PAUL[@]}" -eq 0 ]; then printf '    (nothing)\n'; fi
  if [ "${#LOGOUT_NEEDED[@]}" -gt 0 ]; then
    printf '\n  Log out and back in to finish applying: %s\n' "$(printf '%s; ' "${LOGOUT_NEEDED[@]}" | sed 's/; $//')"
  fi
  if [ "$DRY_RUN" != 1 ]; then
    fix_log "macconfig-check.sh --fix done: ${#FIXED[@]} fixed, ${#NEEDS_PAUL[@]} need Paul; after: $AFTER_DRIFT drift, $AFTER_WARN warning(s)"
  fi
fi

# ---- summary ------------------------------------------------------------
# A few aligned lines, then a one-line verdict. When something needs attention, the
# verdict is followed by one indented bullet per outstanding drift or warning, built
# from ATTN_ITEMS (recorded in bad/warn) — not by scraping the log. After a real
# --fix re-check those bullets are RECHECK_ITEMS, i.e. what's still outstanding.
# Colour only on a tty (C_* are empty under --no-color / NO_COLOR / when piped).
# Nothing parses this text: machines use --health-json, whose attention[] is the
# same bullet text.
#
# Bullet helpers live in this section so tests/check-summary.test.sh (which evals
# from here down to --issues) covers them.

# attn_trim MAX TEXT — shorten TEXT to MAX characters, ending in ...
attn_trim() {
  local max="$1" s="$2" keep
  if [ "${#s}" -le "$max" ]; then
    printf '%s' "$s"
    return 0
  fi
  if [ "$max" -le 3 ]; then
    printf '%s' "${s:0:$max}"
    return 0
  fi
  keep=$((max - 3))
  printf '%s...' "${s:0:$keep}"
}

attn_prepare() {
  if type autofix_class >/dev/null 2>&1; then
    return 0
  fi
  if [ -r "$DOTDIR/lib/autofix-lib.sh" ]; then
    # shellcheck source=lib/autofix-lib.sh disable=SC1091
    . "$DOTDIR/lib/autofix-lib.sh"
  fi
}

# fix: <id> when --fix can repair it, "manual step" for those warnings, else Needs Paul.
attn_hint() {
  local id="$1" cls=""
  if [ "$id" = manual-step ]; then
    printf 'manual step'
    return 0
  fi
  if type autofix_class >/dev/null 2>&1 && [ -r "$DOTDIR/lib/autofix.list" ]; then
    cls="$(autofix_class "$DOTDIR/lib/autofix.list" "$id")"
  fi
  if [ "$cls" = SAFE ]; then
    printf 'fix: %s' "$id"
    return 0
  fi
  printf 'Needs Paul'
}

# One plain bullet body (no indent, no colour): "drift  Section: reason (hint)".
# The whole printed line, including "    - ", stays within ATTN_COLS.
attn_format() {
  local kind="$1" sec="$2" id="$3" msg="$4"
  local secpart="" hint overhead budget cols
  cols="${ATTN_COLS:-100}"
  sec="${sec%% (*}"
  if [ "${#sec}" -gt 32 ]; then
    sec="$(attn_trim 32 "$sec")"
  fi
  if [ -n "$sec" ]; then
    secpart="$sec: "
  fi
  hint="$(attn_hint "$id")"
  # "    - " (6) + kind (5) + two spaces + secpart + " (" + hint + ")"
  overhead=$((6 + 5 + 2 + ${#secpart} + 3 + ${#hint}))
  budget=$((cols - overhead))
  if [ "$budget" -lt 20 ]; then
    budget=20
  fi
  msg="$(attn_trim "$budget" "$msg")"
  printf '%-5s  %s%s (%s)' "$kind" "$secpart" "$msg" "$hint"
}

attn_fill_from() {
  local it ak asec aid amsg formatted
  for it in "$@"; do
    IFS="$US" read -r ak asec aid amsg <<< "$it"
    if [ -z "$ak" ]; then
      continue
    fi
    formatted="$(attn_format "$ak" "$asec" "$aid" "$amsg")"
    ATTN_LINES+=("$formatted")
  done
}

attn_print_lines() {
  local line col
  for line in "$@"; do
    col="$C_WARN"
    case "$line" in
      drift*) col="$C_BAD" ;;
    esac
    printf '    %s- %s%s\n' "$col" "$line" "$C_OFF"
  done
}

SUM_NW=${#CHECKED}                      # number column width = widest count
for n in "$DRIFT" "$WARN" "$HAND" "${#FIXED[@]}" "${#NEEDS_PAUL[@]}" "${#WOULD_FIX[@]}"; do
  if [ "${#n}" -gt "$SUM_NW" ]; then SUM_NW=${#n}; fi
done
# sum_row GLYPH GLYPH-CELLS LABEL COUNT COLOUR [SUFFIX] — zero counts are dimmed.
sum_row() {
  local col="$5" lw=12
  if [ "$4" = 0 ]; then col="$C_DIM"; fi
  lw=$((lw - $2 + 1))                   # a 2-cell (emoji) glyph eats one pad space
  printf '  %s%s %-*s %*s%s%s\n' "$col" "$1" "$lw" "$3" "$SUM_NW" "$4" "${6:-}" "$C_OFF"
}
S_DRIFT="$AFTER_DRIFT"; S_WARN="$AFTER_WARN"; S_DRIFT_NOTE=""; S_WARN_NOTE=""
if [ "$FIX" = 1 ] && [ "$DRY_RUN" != 1 ]; then   # after --fix: what's left, and what it was
  if [ "$S_DRIFT" != "$DRIFT" ]; then S_DRIFT_NOTE="   (was $DRIFT before --fix)"; fi
  if [ "$S_WARN" != "$WARN" ]; then S_WARN_NOTE="   (was $WARN before --fix)"; fi
fi
S_OK_COL="$C_OK"; if [ "$OKS" != "$CHECKED" ]; then S_OK_COL=""; fi

printf '\n%sSummary%s\n' "$C_HDR" "$C_OFF"
sum_row "✔" 1 "ok"       "$OKS"     "$S_OK_COL" " / $CHECKED"
sum_row "✖" 1 "drift"    "$S_DRIFT" "$C_BAD"    "$S_DRIFT_NOTE"
sum_row "⚠" 1 "warnings" "$S_WARN"  "$C_WARN"   "$S_WARN_NOTE"
sum_row "✋" 2 "by hand"  "$HAND"    ""         "   (manualsteps list)"
if [ "$FIX" = 1 ]; then
  if [ "$DRY_RUN" = 1 ]; then
    sum_row "↻" 1 "would fix" "${#WOULD_FIX[@]}" "$C_OK" "   (dry run: nothing changed)"
  else
    sum_row "↻" 1 "fixed"     "${#FIXED[@]}" "$C_OK"
  fi
  sum_row "☞" 1 "needs Paul" "${#NEEDS_PAUL[@]}" "$C_WARN"
else
  # How many of today's issues `--fix` would repair (SAFE rows of lib/autofix.list).
  S_SAFE=0
  if [ "${#FIX_ITEMS[@]}" -gt 0 ] && [ -r "$DOTDIR/lib/autofix-lib.sh" ] && [ -r "$DOTDIR/lib/autofix.list" ]; then
    # shellcheck source=lib/autofix-lib.sh disable=SC1091
    . "$DOTDIR/lib/autofix-lib.sh"
    for it in "${FIX_ITEMS[@]}"; do
      IFS="$US" read -r _ it_id _ _ <<< "$it"
      if [ "$(autofix_class "$DOTDIR/lib/autofix.list" "$it_id")" = SAFE ]; then S_SAFE=$((S_SAFE + 1)); fi
    done
  fi
  if [ "$S_SAFE" -gt 0 ]; then
    printf '  %s→ run ./macconfig-check.sh --fix to repair %d safe item(s)%s\n' "$C_OK" "$S_SAFE" "$C_OFF"
  fi
fi
S_ATTN=$((S_DRIFT + S_WARN))
if [ "$S_ATTN" -eq 0 ]; then
  printf '  %sAll good%s\n' "$C_OK$C_HDR" "$C_OFF"
else
  S_VCOL="$C_WARN"; if [ "$S_DRIFT" -gt 0 ]; then S_VCOL="$C_BAD"; fi
  S_NEED="need"; if [ "$S_ATTN" -eq 1 ]; then S_NEED="needs"; fi
  S_WHAT=""
  if [ "$S_DRIFT" -gt 0 ]; then S_WHAT="$S_DRIFT drift"; fi
  if [ "$S_WARN" -gt 0 ]; then
    S_W="warnings"; if [ "$S_WARN" -eq 1 ]; then S_W="warning"; fi
    S_WHAT="${S_WHAT:+$S_WHAT, }$S_WARN $S_W"
  fi
  printf '  %s%d %s attention%s (%s)\n' "$S_VCOL$C_HDR" "$S_ATTN" "$S_NEED" "$C_OFF" "$S_WHAT"
fi
# Outstanding drift and warnings only. By-hand info lines are not in these arrays,
# and a clean run (S_ATTN = 0) prints nothing extra. ATTN_LINES is also attention[].
ATTN_LINES=()
if [ "$S_ATTN" -gt 0 ]; then
  attn_prepare
  if [ "${RECHECK_RAN:-0}" = 1 ]; then
    attn_fill_from ${RECHECK_ITEMS[@]+"${RECHECK_ITEMS[@]}"}
  else
    attn_fill_from ${ATTN_ITEMS[@]+"${ATTN_ITEMS[@]}"}
  fi
  attn_print_lines ${ATTN_LINES[@]+"${ATTN_LINES[@]}"}
fi

# ---- --issues (internal; used by --fix to re-check) ----------------------
# kind, id, arg, message (FIX_ITEMS), then the section recorded alongside it.
if [ "$ISSUES" = 1 ]; then
  i=0
  for it in ${FIX_ITEMS[@]+"${FIX_ITEMS[@]}"}; do
    asec=""
    if [ "$i" -lt "${#ATTN_ITEMS[@]}" ]; then
      IFS="$US" read -r _ak asec _aid _amsg <<< "${ATTN_ITEMS[$i]}"
    fi
    printf '%s%s%s\n' "$it" "$US" "$asec" >&3
    i=$((i + 1))
  done
fi

# ---- --health-json -------------------------------------------------------
if [ "$HEALTH_JSON" = 1 ]; then
  json_str() {  # JSON string literal (escapes \ " and control characters)
    local v="$1"
    v="${v//\\/\\\\}"; v="${v//\"/\\\"}"
    v="${v//$'\n'/\\n}"; v="${v//$'\t'/\\t}"; v="${v//$'\r'/\\r}"
    printf '"%s"' "$v"
  }
  json_num() { case "$1" in ''|*[!0-9]*) printf 'null' ;; *) printf '%s' "$1" ;; esac; }
  json_opt() { if [ -n "$1" ]; then json_str "$1"; else printf 'null'; fi; }
  json_dec() { if printf '%s' "$1" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then printf '%s' "$1"; else printf 'null'; fi; }
  json_crash_apps() {  # "app|count"... -> {"app": count, ...}
    local first=1 x
    printf '{'
    for x in "$@"; do
      [ "$first" = 1 ] || printf ', '
      first=0; printf '%s: %s' "$(json_str "${x%|*}")" "$(json_num "${x##*|}")"
    done
    printf '}'
  }
  json_jobs() {  # "label|loaded(yes/no)|last_exit"... -> [{...}, ...]
    local first=1 x label rest loaded ex jb
    printf '['
    for x in "$@"; do
      label="${x%%|*}"; rest="${x#*|}"; loaded="${rest%%|*}"; ex="${rest#*|}"
      [ "$first" = 1 ] || printf ', '
      first=0
      jb=false
      if [ "$loaded" = yes ]; then jb=true; fi
      printf '{"label": %s, "loaded": %s, "last_exit": %s}' "$(json_str "$label")" \
        "$jb" "$(json_num "$ex")"
    done
    printf ']'
  }
  json_arr() {  # json_arr item... -> ["a","b"]
    local first=1 x
    printf '['
    for x in "$@"; do
      [ "$first" = 1 ] || printf ','
      first=0; json_str "$x"
    done
    printf ']'
  }
  {
    printf '{\n'
    printf '  "generated": %s,\n' "$(json_str "$(date '+%Y-%m-%dT%H:%M:%S%z')")"
    printf '  "host": %s,\n' "$(json_str "$(scutil --get ComputerName 2>/dev/null || hostname)")"
    printf '  "summary": {"checked": %d, "ok": %d, "drift": %d, "warnings": %d, "by_hand": %d},\n' \
      "$CHECKED" "$OKS" "$DRIFT" "$WARN" "$HAND"
    printf '  "battery": {"status": %s, "condition": %s, "max_capacity_pct": %s, "cycle_count": %s},\n' \
      "$(json_str "$H_BAT_STATUS")" "$(json_opt "$H_BAT_COND")" "$(json_num "$H_BAT_MAX")" "$(json_num "$H_BAT_CYCLES")"
    printf '  "disk": {"status": %s, "free_gb": %s, "free_pct": %s, "total_gb": %s},\n' \
      "$(json_str "$H_DISK_STATUS")" "$(json_num "$H_DISK_FREE_GB")" "$(json_num "$H_DISK_FREE_PCT")" "$(json_num "$H_DISK_TOTAL_GB")"
    printf '  "uptime": {"status": %s, "days": %s},\n' "$(json_str "$H_UP_STATUS")" "$(json_num "$H_UP_DAYS")"
    printf '  "memory": {"status": %s, "pressure": %s, "free_pct": %s, "swap_used_gb": %s},\n' \
      "$(json_str "$H_MEM_STATUS")" "$(json_str "$H_MEM_PRESSURE")" "$(json_num "$H_MEM_FREE_PCT")" "$(json_dec "$H_MEM_SWAP_GB")"
    printf '  "storage": {"status": %s, "caches_gb": %s, "docker_gb": %s, "brew_cache_gb": %s, "derived_data_gb": %s},\n' \
      "$(json_str "$H_STO_STATUS")" "$(json_dec "$H_STO_CACHES")" "$(json_dec "$H_STO_DOCKER")" "$(json_dec "$H_STO_BREW")" "$(json_dec "$H_STO_DERIVED")"
    printf '  "security": {"status": %s, "firewall": %s, "gatekeeper": %s, "sip": %s, "remote_login": %s, "screen_sharing": %s, "file_sharing": %s, "screen_lock": %s},\n' \
      "$(json_str "$H_SEC_STATUS")" "$(json_str "$H_SEC_FIREWALL")" "$(json_str "$H_SEC_GATEKEEPER")" "$(json_str "$H_SEC_SIP")" \
      "$(json_str "$H_SEC_SSH")" "$(json_str "$H_SEC_SCREENSHARING")" "$(json_str "$H_SEC_FILESHARING")" "$(json_str "$H_SEC_SCREENLOCK")"
    printf '  "mdm": {"status": %s, "enrolled": %s, "agent_running": %s},\n' \
      "$(json_str "$H_MDM_STATUS")" "$(json_str "$H_MDM_ENROLLED")" "$(json_str "$H_MDM_AGENT")"
    printf '  "crashes": {"status": %s, "days": %s, "kernel_panics": %s, "app_crashes": %s, "user_faults": %s, "by_app": %s, "panic_files": %s},\n' \
      "$(json_str "$H_CR_STATUS")" "$(json_num "$HEALTH_CRASH_DAYS")" "$(json_num "$H_CR_PANICS")" "$(json_num "$H_CR_CRASHES")" "$(json_num "$H_CR_FAULTS")" \
      "$(json_crash_apps ${H_CR_APPS[@]+"${H_CR_APPS[@]}"})" "$(json_arr ${H_CR_PANIC_FILES[@]+"${H_CR_PANIC_FILES[@]}"})"
    printf '  "background_jobs": {"status": %s, "hammerspoon_running": %s, "launch_agents": %s},\n' \
      "$(json_str "$H_JOBS_STATUS")" "$(json_str "$H_HS_RUNNING")" "$(json_jobs ${H_JOBS[@]+"${H_JOBS[@]}"})"
    printf '  "dotfiles": {"status": %s, "uncommitted": %s, "ahead": %s, "behind": %s, "last_fetch": %s},\n' \
      "$(json_str "$H_GIT_STATUS")" "$(json_num "$H_GIT_DIRTY")" "$(json_num "$H_GIT_AHEAD")" "$(json_num "$H_GIT_BEHIND")" "$(json_opt "$H_GIT_FETCHED")"
    printf '  "login_items": {"status": %s, "enabled": %d, "allow_listed": %d, "mdm_approved": %d, "unknown": %s, "stale": %s},\n' \
      "$(json_str "$H_LI_STATUS")" "$H_LI_ENABLED" "$H_LI_ALLOW" "$H_LI_MDM" \
      "$(json_arr ${H_LI_UNKNOWN[@]+"${H_LI_UNKNOWN[@]}"})" "$(json_arr ${H_LI_STALE[@]+"${H_LI_STALE[@]}"})"
    if [ "$FIX" = 1 ]; then
      if [ "$DRY_RUN" = 1 ]; then fix_mode=dry-run; else fix_mode=apply; fi
      printf '  "fix": {"mode": %s, "after": {"drift": %d, "warnings": %d}},\n' "$(json_str "$fix_mode")" "$AFTER_DRIFT" "$AFTER_WARN"
      printf '  "fixed": %s,\n' "$(json_arr ${FIXED[@]+"${FIXED[@]}"})"
      printf '  "would_fix": %s,\n' "$(json_arr ${WOULD_FIX[@]+"${WOULD_FIX[@]}"})"
      printf '  "needs_paul": %s,\n' "$(json_arr ${NEEDS_PAUL[@]+"${NEEDS_PAUL[@]}"})"
      printf '  "logout_needed": %s,\n' "$(json_arr ${LOGOUT_NEEDED[@]+"${LOGOUT_NEEDED[@]}"})"
    fi
    printf '  "drift_messages": %s,\n' "$(json_arr ${DRIFT_MSGS[@]+"${DRIFT_MSGS[@]}"})"
    printf '  "warning_messages": %s,\n' "$(json_arr ${WARN_MSGS[@]+"${WARN_MSGS[@]}"})"
    printf '  "attention": %s\n' "$(json_arr ${ATTN_LINES[@]+"${ATTN_LINES[@]}"})"
    printf '}\n'
  } >&3
fi

# With --fix (not a dry run) the exit status reflects the drift left after the fixes.
if [ "$AFTER_DRIFT" -gt 0 ]; then exit 1; fi
exit 0
