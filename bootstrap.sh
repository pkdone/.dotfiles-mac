#!/usr/bin/env bash
#
# bootstrap.sh — set up this machine end to end by running the individual scripts in
# order, each behind a confirmation prompt:
#
#   1. install.sh   symlinks, Brewfile, mise trust
#   2. shell.sh     make fish the login shell
#   3. hostname.sh  set HostName / LocalHostName / ComputerName
#   4. macos.sh     apply the managed macOS defaults
#   5. dock.sh      pin the Dock apps in order
#   6. handlers.sh  set URL-scheme default apps (mailto → Chrome) and Finder file handlers
#   7. prune-apps.sh remove unwanted App Store apps (GarageBand, iMovie)
#
# It ends by printing the manual steps (lib/manual-steps.list: permissions, sign-ins,
# by-hand settings) and, on a terminal, offering scripts/manual-steps.sh open.
#
# Every underlying script is idempotent, so bootstrap.sh is safe to re-run — an
# already-configured machine is a no-op. The scripts can still be run individually;
# this is just the guided "do everything" entrypoint.
#
# Flags:
#   --dry-run    Preview every step (using each script's own preview mode); change nothing.
#   --yes, -y    Don't prompt before each step (sub-scripts may still prompt for sudo).
#   -h, --help   Show usage.
#
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRYRUN=0
ASSUME_YES=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRYRUN=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    -h|--help)
      cat <<'USAGE'
Usage: bootstrap.sh [--dry-run] [--yes]
  Run the full machine setup in order: install.sh, shell.sh, hostname.sh,
  macos.sh, dock.sh, handlers.sh, prune-apps.sh — each behind a confirmation prompt. Idempotent and safe
  to re-run. Ends with the checklist of manual steps (scripts/manual-steps.sh).
  --dry-run    Preview every step (each script's own preview mode); change nothing.
  --yes, -y    Don't prompt before each step (sub-scripts may still prompt for sudo).
  -h, --help   Show this help.
USAGE
      exit 0 ;;
    *) echo "Unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

# ---- logging / prompts --------------------------------------------------
if [ -t 1 ]; then C_HDR=$'\033[1m'; C_OFF=$'\033[0m'; else C_HDR=''; C_OFF=''; fi
banner() { printf '\n%s== %s ==%s\n' "$C_HDR" "$1" "$C_OFF"; }

confirm() {  # prompt -> 0 to proceed, 1 to skip
  [ "$ASSUME_YES" = 1 ] && return 0
  printf '%s [y/N] ' "$1"
  read -r reply || reply=''
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# Before the Dock step, flag any app in lib/dock-apps.list that isn't installed yet
# (e.g. the manual installs under README "Apps not in the Brewfile"). dock.sh already
# skips a missing app, so this just surfaces it before the confirm below — install them
# first and answer N, or proceed and re-run dock.sh later. Mirrors dock.sh's own parsing.
precheck_dock() {
  local list="$DOTDIR/lib/dock-apps.list" name path apps
  local missing=()
  [ -r "$list" ] || return 0
  apps="$(<"$list")"
  while IFS='|' read -r name path; do
    case "$name" in ''|'#'*) continue ;; esac
    path="${path/@HOME@/$HOME}"
    # Expand the one globbed path (WhatsApp) the same way dock.sh does.
    # shellcheck disable=SC2086  # intentional: unquoted $path lets the glob expand
    case "$path" in *'*'*) set -- $path; path="$1" ;; esac
    [ -e "$path" ] || missing+=("$name")
  done <<< "$apps"
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "  ⚠️  Not installed yet — dock.sh will skip these:"
    for name in "${missing[@]}"; do echo "        - $name"; done
    echo '      Install them first (README → "Apps not in the Brewfile"), then answer N below'
    echo "      and re-run dock.sh afterwards (or proceed now and re-run later)."
  fi
  return 0
}

# ---- preflight: the scripts we orchestrate must be present & executable --
for s in install.sh shell.sh hostname.sh macos.sh dock.sh handlers.sh prune-apps.sh; do
  [ -x "$DOTDIR/$s" ] || { echo "Error: $DOTDIR/$s missing or not executable." >&2; exit 1; }
done

# ---- run one step -------------------------------------------------------
# step NUM "label" SCRIPT PREVIEW_FLAG
#   PREVIEW_FLAG is the script's own preview option (--dry-run, --list), or "" for a
#   script with no preview mode (install.sh) — that one is described, not run, in --dry-run.
step() {
  local num="$1" label="$2" script="$3" preview="$4" precheck="${5:-}"
  banner "$num/7  $label"
  if [ -n "$precheck" ]; then "$precheck"; fi
  if [ "$DRYRUN" = 1 ]; then
    if [ -n "$preview" ]; then
      "$DOTDIR/$script" "$preview"
    else
      echo "  (dry-run) would run $script — it has no preview mode and makes changes."
    fi
    return 0
  fi
  if confirm "Run $script now?"; then
    "$DOTDIR/$script"
  else
    echo "  skipped."
  fi
}

echo "bootstrap.sh — $([ "$DRYRUN" = 1 ] && echo 'DRY RUN (previewing every step)' || echo 'guided setup')"

# install.sh would otherwise print the manual-steps checklist mid-run; show it once at the end.
export DOTFILES_BOOTSTRAP=1

step 1 "install.sh — symlinks, Brewfile, mise trust"  install.sh  ""
step 2 "shell.sh — make fish the login shell"         shell.sh    --dry-run
step 3 "hostname.sh — set host names"                 hostname.sh --dry-run
step 4 "macos.sh — apply managed macOS defaults"      macos.sh    --dry-run
step 5 "dock.sh — pin the Dock apps in order"         dock.sh     --list      precheck_dock
step 6 "handlers.sh — URL schemes and Finder file handlers"   handlers.sh --dry-run
step 7 "prune-apps.sh — remove unwanted apps"         prune-apps.sh --dry-run

banner "Done"
if [ "$DRYRUN" = 1 ]; then
  echo "Dry run only — nothing was changed. Re-run without --dry-run to apply."
else
  echo "Setup complete. Run macconfig (or ./macconfig-check.sh) to verify the machine matches the repo."
fi

# Manual steps (permissions, sign-ins, by-hand settings) from lib/manual-steps.list.
MANUAL_STEPS="$DOTDIR/scripts/manual-steps.sh"
echo ""
"$MANUAL_STEPS" list || true
# The walk-through is interactive by nature: offer it only on a real run, on a terminal,
# and not under --yes.
if [ "$DRYRUN" = 0 ] && [ "$ASSUME_YES" = 0 ] && [ -t 0 ] && [ -t 1 ]; then
  echo ""
  printf 'Walk through the manual steps now, opening each settings page? [y/N] '
  read -r reply || reply=''
  case "$reply" in
    y|Y|yes|YES) "$MANUAL_STEPS" open || true ;;
    *) echo "Later: $MANUAL_STEPS open" ;;
  esac
fi
