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
# Right after install.sh it names any missing company app and, on a terminal,
# offers to open Fleet Self service. That does not install the app.
#
# A step that exits non-zero is recorded. Later steps still run, including that
# manual-steps list and walk-through. The end of the run names the failed steps
# and the log path, then exits with an error.
#
# Every underlying script is idempotent, so bootstrap.sh is safe to re-run — an
# already-configured machine is a no-op. The scripts can still be run individually;
# this is just the guided "do everything" entrypoint.
#
# Each run is copied to ~/Library/Logs/dotfiles/bootstrap-YYYYMMDD-HHMMSS.log.
# Do not run this script as root.
#
# Flags:
#   --dry-run    Preview every step (using each script's own preview mode); change nothing.
#   --yes, -y    Don't prompt before each step (sub-scripts may still prompt for sudo).
#   -h, --help   Show usage.
#
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/dotfiles-log.sh disable=SC1091
. "$DOTDIR/lib/dotfiles-log.sh"
# shellcheck source=lib/fleet-apps.sh disable=SC1091
. "$DOTDIR/lib/fleet-apps.sh"
dotfiles_refuse_root "bootstrap.sh"

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
  to re-run. After install.sh, names any missing company app and, in a terminal,
  offers to open Fleet Self service. A missing company app is a warning, not a
  failed step. Ends with the checklist of manual steps (scripts/manual-steps.sh).
  A step that fails is recorded. Later steps still run. At the end the failed
  steps and the log path are printed, and this script exits with an error.
  --dry-run    Preview every step (each script's own preview mode); change nothing.
  --yes, -y    Don't prompt before each step (sub-scripts may still prompt for sudo).
  -h, --help   Show this help.
USAGE
      exit 0 ;;
    *) echo "Unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

# Help and unknown arguments exit above, so a log is only opened for a real run.
dotfiles_log_exec bootstrap "$@"

# macos.sh appends settings that still need a logout. Printed at the very end.
if [ -n "${DOTFILES_LOG_FILE:-}" ]; then
  export DOTFILES_LOGOUT_FILE="${DOTFILES_LOG_FILE}.logout"
fi

# ---- logging / prompts --------------------------------------------------
# stdout is tee'd into the log, so it is not a tty. Colour follows the outer
# terminal, which the log wrapper recorded before the redirect.
if [ "${DOTFILES_STDOUT_TTY:-}" = 1 ] || { [ -z "${DOTFILES_STDOUT_TTY:-}" ] && [ -t 1 ]; }; then
  C_HDR=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_HDR=''; C_OFF=''
fi
banner() { printf '\n%s== %s ==%s\n' "$C_HDR" "$1" "$C_OFF"; }

confirm() {  # prompt -> 0 to proceed, 1 to skip
  [ "$ASSUME_YES" = 1 ] && return 0
  printf '%s [y/N] ' "$1"
  read -r reply || reply=''
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# Before the Dock step, flag any app in lib/dock-apps.list that isn't installed yet
# (e.g. the manual installs under docs/setup.md "Apps not in the Brewfile"). dock.sh already
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
    # Expand a globbed path the same way dock.sh does.
    # shellcheck disable=SC2086  # intentional: unquoted $path lets the glob expand
    case "$path" in *'*'*) set -- $path; path="$1" ;; esac
    [ -e "$path" ] || missing+=("$name")
  done <<< "$apps"
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "  ⚠️  Not installed yet — dock.sh will skip these:"
    for name in "${missing[@]}"; do echo "        - $name"; done
    echo '      Install them first (docs/setup.md → "Apps not in the Brewfile"), then answer N below'
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
#
# set -e is on, and the log wrapper tees this whole script. A bare non-zero
# status from a step would exit here, close that tee, and skip every later
# step including the manual-steps list. Capture the status instead. The
# wrapper still exits with the status printed at the end of the run.
# FAILED_STEPS holds "step N script (exit C)" for each failure.
FAILED_STEPS=()
step() {
  local num="$1" label="$2" script="$3" preview="$4" precheck="${5:-}"
  local rc=0
  banner "$num/7  $label"
  if [ -n "$precheck" ]; then "$precheck"; fi
  if [ "$DRYRUN" = 1 ]; then
    if [ -n "$preview" ]; then
      "$DOTDIR/$script" "$preview" || rc=$?
    else
      echo "  (dry-run) would run $script — it has no preview mode and makes changes."
    fi
  elif confirm "Run $script now?"; then
    "$DOTDIR/$script" || rc=$?
  else
    echo "  skipped."
  fi
  if [ "$rc" -ne 0 ]; then
    echo "  $script failed (exit $rc). Continuing with the remaining steps."
    FAILED_STEPS+=("step $num $script (exit $rc)")
  fi
}

echo "bootstrap.sh — $([ "$DRYRUN" = 1 ] && echo 'DRY RUN (previewing every step)' || echo 'guided setup')"

# install.sh would otherwise print the manual-steps checklist mid-run; show it once at the end.
export DOTFILES_BOOTSTRAP=1

step 1 "install.sh — symlinks, Brewfile, mise trust"  install.sh  ""
# Company apps are not in the Brewfile. Name any that are missing and, on a
# terminal, offer to open Fleet Self service. --yes and --dry-run only print
# how to install them. A missing app is a warning; setup continues.
if [ "$DRYRUN" = 1 ] || [ "$ASSUME_YES" = 1 ]; then
  FLEET_OFFER=0
else
  FLEET_OFFER=1
fi
fleet_company_apps_prompt "$DOTDIR/lib/mdm-apps.list"
step 2 "shell.sh — make fish the login shell"         shell.sh    --dry-run
step 3 "hostname.sh — set host names"                 hostname.sh --dry-run
step 4 "macos.sh — apply managed macOS defaults"      macos.sh    --dry-run
step 5 "dock.sh — pin the Dock apps in order"         dock.sh     --list      precheck_dock
step 6 "handlers.sh — URL schemes and Finder file handlers"   handlers.sh --dry-run
step 7 "prune-apps.sh — remove unwanted apps"         prune-apps.sh --dry-run

banner "Done"
if [ "$DRYRUN" = 1 ]; then
  if [ "${#FAILED_STEPS[@]}" -gt 0 ]; then
    echo "Dry run only — nothing was changed. Some previews failed. The list is at the end."
  else
    echo "Dry run only — nothing was changed. Re-run without --dry-run to apply."
  fi
elif [ "${#FAILED_STEPS[@]}" -gt 0 ]; then
  echo "Setup finished with failed steps. The manual steps are below. The list of failed steps is at the end."
else
  echo "Setup complete. Run macconfig (or ./macconfig-check.sh) to verify the machine matches the repo."
fi

# Manual steps (permissions, sign-ins, by-hand settings) from lib/manual-steps.list.
# Auto-brightness cannot be written from here (admin password, root-owned
# plist). Name it before the long checklist so it is not lost in the list.
# Its open action is System Settings → Displays.
MANUAL_STEPS="$DOTDIR/scripts/manual-steps.sh"
echo ""
printf '%sStill by hand: Automatically adjust brightness Off%s\n' "$C_HDR" "$C_OFF"
echo "  System Settings → Displays. The manual-steps walk-through opens this page."
echo "  Setup leaves it alone: changing it needs an admin password, and the saved"
echo "  value is a root-owned file. Leave True Tone and Slightly dim the display"
echo "  on battery as they are."
echo ""
"$MANUAL_STEPS" list || true
# The walk-through is interactive by nature: offer it only on a real run, on a terminal,
# and not under --yes.
if [ "$DRYRUN" = 0 ] && [ "$ASSUME_YES" = 0 ] && dotfiles_is_interactive; then
  echo ""
  printf 'Walk through the manual steps now, opening each settings page? [y/N] '
  read -r reply || reply=''
  case "$reply" in
    y|Y|yes|YES) "$MANUAL_STEPS" open || true ;;
    *) echo "Later: $MANUAL_STEPS open" ;;
  esac
fi

# Very end. macos.sh notes anything it changed that still needs a logout
# (trackpad rows are omitted when activateSettings -u succeeded).
if [ "$DRYRUN" != 1 ]; then
  dotfiles_print_logout_notice "$C_HDR" "$C_OFF"
fi

if [ "${#FAILED_STEPS[@]}" -gt 0 ]; then
  echo ""
  echo "These steps failed. Setup still ran the rest, including the manual steps."
  for item in "${FAILED_STEPS[@]}"; do
    echo "  - $item"
  done
  if [ -n "${DOTFILES_LOG_FILE:-}" ]; then
    echo "Log file: ${DOTFILES_LOG_FILE}"
  else
    echo "Log file: ~/Library/Logs/dotfiles/ (this run did not open a log)"
  fi
  exit 1
fi
