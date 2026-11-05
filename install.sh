#!/usr/bin/env bash
#
# install.sh — bootstrap this machine: symlink configs into ~/.config, install the
# Cursor origin CLI when ~/.local/bin/origin is missing or not executable, install
# the Brewfile, start Hammerspoon if it is installed and not running, turn Tailscale
# on and select its recommended exit node when that CLI is signed in, and trust the
# mise config. Login shell, hostname, macOS defaults and the Dock are separate
# scripts; bootstrap.sh runs the whole sequence in order. Ends by printing the
# manual steps (lib/manual-steps.list) and, on a terminal, offering to walk
# through them.
#
# Flags:
#   --dry-run    Describe the steps, including the origin install, the Hammerspoon start, and Tailscale; change nothing.
#   -h, --help   Show usage.
#
# Safe to re-run. Existing correct symlinks are repointed harmlessly; if a *real*
# file is ever in the way of a symlink, it's moved into backups/pre-symlink-<ts>/
# rather than clobbered. Also mkdir -p ~/Pictures/Screenshots (screenshot save
# location). Existing files are not moved. Login LaunchAgents are rendered
# (not symlinked): scripts/install-launchagent.sh replaces @HOME@ with $HOME
# because launchd does not expand ~ or $HOME, then load-launchagent.sh --reload
# bootout/bootstraps the job so WatchPaths is picked up.
#
# Each run is copied to ~/Library/Logs/dotfiles/install-YYYYMMDD-HHMMSS.log.
# The Brewfile install retries a missing entry once and names anything still
# missing. If that step itself stops before it can name anything, the summary
# says the install failed and points at the log. Do not run this script as root.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/dotfiles-log.sh disable=SC1091
. "$SCRIPT_DIR/lib/dotfiles-log.sh"
# shellcheck source=lib/safe-fixers.sh disable=SC1091
. "$SCRIPT_DIR/lib/safe-fixers.sh"
dotfiles_refuse_root "install.sh"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      cat <<'USAGE'
Usage: install.sh [--dry-run]
  Symlink configs, install the Cursor origin CLI when ~/.local/bin/origin is
  missing or not executable, install the Brewfile, and trust mise. After the
  Hammerspoon cask and the hammerspoon/ symlink, start Hammerspoon if it is
  installed and not already running. When the Tailscale CLI is signed in,
  turn it on if it is stopped and select the recommended exit node when none
  is selected. Idempotent. The origin install, the Hammerspoon start, and
  Tailscale are lib/safe-fixers.sh, the same helpers macconfig --fix uses.
  --dry-run    Describe those steps, including origin, the Hammerspoon start, and Tailscale; change nothing.
  -h, --help   Show this help.
USAGE
      exit 0 ;;
    *) echo "Unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

if [ "$DRY_RUN" = 1 ]; then
  echo "install.sh — dry run (nothing is changed)"
  echo "  would symlink configs from lib/links.list, including hammerspoon/ → ~/.hammerspoon"
  echo "  Origin CLI:"
  safe_install_origin
  echo "  would install the Brewfile, including the Hammerspoon cask"
  echo "  would render login LaunchAgents, trust mise, and enable the pre-push hook"
  echo "  Hammerspoon:"
  # The cask install above would put the app on disk first, so describe the
  # start even when Hammerspoon.app is not there yet. The real run below uses
  # the same helper with DRY_RUN unset.
  SAFE_HAMMERSPOON_DESCRIBE=1 safe_start_hammerspoon
  echo "  Tailscale:"
  safe_tailscale_exit || true
  echo "Dry run complete."
  exit 0
fi

if [ "$(uname -s)" != Darwin ]; then
  echo "install.sh is for macOS (Darwin); detected $(uname -s). Aborting." >&2
  exit 1
fi

dotfiles_log_exec install "$@"

DOTFILES="$HOME/.dotfiles-mac"

# Fail early with a clear message if a required data file is missing.
require_file() { [ -r "$1" ] || { echo "Error: required file not found: $1" >&2; exit 1; }; }

# ---- preflight ----------------------------------------------------------
# Surface must-do-by-hand things up front as warnings, so later steps don't fail
# cryptically. Network, Command Line Tools, disk space, and Homebrew's own
# health are checked immediately before the Brewfile install.
if command -v gh >/dev/null 2>&1 && ! gh auth status >/dev/null 2>&1; then
  echo "⚠️  gh is installed but not authenticated — run 'gh auth login' if you need private repos."
fi

# ---- symlink helper -----------------------------------------------------
# link SRC DST: point DST at SRC. If DST is already a symlink, repoint it (idempotent).
# If a real file/dir sits at DST, move it into a timestamped backup dir first so the
# bootstrap never destroys pre-existing data.
BACKUP_DIR=""
ensure_backup_dir() {
  if [ -z "$BACKUP_DIR" ]; then
    BACKUP_DIR="$DOTFILES/backups/pre-symlink-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
  fi
}

link() {  # src dst
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  # If dst is a symlink, replace it. If dst is a real file/dir, back it up first.
  if [ -L "$dst" ]; then
    rm -f "$dst"
  elif [ -e "$dst" ]; then
    ensure_backup_dir
    mv "$dst" "$BACKUP_DIR/"
    echo "  backed up existing $dst -> $BACKUP_DIR/"
  fi
  ln -sfn "$src" "$dst"
  echo "  linked $dst"
}

# Screenshot save location (com.apple.screencapture location). macos.sh mkdir -p's
# the same folder again before writing the default, including from macconfig --fix.
# Existing files are not moved.
echo ""
echo "📁 Developer folder (repos live here)..."
mkdir -p "$HOME/Developer"
echo "  $HOME/Developer"

echo "📁 Screenshots folder..."
mkdir -p "$HOME/Pictures/Screenshots"
echo "  $HOME/Pictures/Screenshots"

echo ""
echo "🔗 Creating symlinks..."
require_file "$DOTFILES/lib/links.list"
# Static one-to-one links live in lib/links.list (shared with macconfig-check.sh).
while IFS='|' read -r src tgt; do
  case "$src" in ''|'#'*) continue ;; esac
  link "$DOTFILES/$src" "${tgt//@HOME@/$HOME}"
done < "$DOTFILES/lib/links.list"
# Fish functions are one-dir-to-many, so handle the glob as a special case.
mkdir -p "$HOME/.config/fish/conf.d"   # keep the (currently empty) drop-in dir
for f in "$DOTFILES"/fish/functions/*.fish; do
  link "$f" "$HOME/.config/fish/functions/$(basename "$f")"
done

if [ -n "$BACKUP_DIR" ]; then
  echo "  (real files were moved to $BACKUP_DIR)"
fi

echo ""
echo "📦 Origin CLI (Cursor; ~/.local/bin/origin)..."
# gitconfig's credential helper is this path. Homebrew has no formula. The
# helper downloads only when the file is missing or not executable, and puts
# the repo gitconfig back if the installer rewrites it. A failure
# does not stop the rest of setup: the Login shell check warns, and a later
# run (or macconfig --fix) tries again.
origin_rc=0
safe_install_origin || origin_rc=$?
if [ "$origin_rc" -ne 0 ]; then
  echo "  not installed."
fi

echo ""
echo "🚀 Installing login LaunchAgents (dictation 164, Quick Note 190)..."
for LA_SRC in "$DOTFILES"/launchagents/*.plist; do
  [ -f "$LA_SRC" ] || continue
  LA_LABEL="$(basename "$LA_SRC" .plist)"
  LA_PLIST="$HOME/Library/LaunchAgents/${LA_LABEL}.plist"
  # Render @HOME@ -> $HOME, then bootout/bootstrap so WatchPaths takes effect.
  # Shared with macconfig-check.sh --fix (that path reloads only when the
  # installed plist differs, or bootstraps when the job isn't loaded).
  if ! "$DOTFILES/scripts/install-launchagent.sh" --write "$LA_LABEL"; then
    echo "  ⚠️  could not render $LA_LABEL"
    continue
  fi
  if "$DOTFILES/scripts/load-launchagent.sh" --reload "$LA_PLIST" >/dev/null; then
    echo "  loaded $LA_LABEL"
  else
    echo "  ⚠️  could not bootstrap $LA_LABEL — run: launchctl bootstrap gui/$(id -u) $LA_PLIST"
  fi
done

echo ""
echo "🍺 Installing from Brewfile..."
# One failed entry must not abort the rest of setup. The helper retries each
# miss once, names whatever is still missing, and returns non-zero. mise trust,
# the hook, and the manual-steps list still run.
bundle_rc=0
"$SCRIPT_DIR/scripts/brew-bundle-install.sh" --install-homebrew --file "$DOTFILES/Brewfile" || bundle_rc=$?

# The hammerspoon/ symlink is earlier in this script (lib/links.list). The cask
# install is the Brewfile step above. Start the app only when both of those
# have been attempted, and only if it is installed and not already running.
# A missing app does not fail setup: the Brewfile summary above already named
# it. Same helper as macconfig-check.sh --fix (lib/safe-fixers.sh).
echo ""
echo "🥄 Hammerspoon (start it when it is installed and not already running)..."
# Return 2 means the app is not installed yet. The Brewfile summary above
# already named a missing cask, and a later run of this script starts it.
# Do not fail the rest of setup for that.
hs_rc=0
safe_start_hammerspoon || hs_rc=$?
if [ "$hs_rc" -eq 1 ]; then
  echo "  not started."
fi

echo ""
echo "Tailscale (turn it on when it is signed in, and select the recommended exit node when none is selected)..."
# Same helper as macconfig --fix. A missing CLI, a signed-out app, an offline
# daemon, or a managed policy that refuses the exit node does not stop setup.
# The helper already says which of those it was. No sudo.
ts_rc=0
safe_tailscale_exit || ts_rc=$?
if [ "$ts_rc" -ne 0 ]; then
  echo "  left unchanged."
fi

echo ""
echo "🔧 Trusting mise config..."
if command -v brew >/dev/null 2>&1; then
  "$(brew --prefix)/bin/mise" trust "$DOTFILES/mise/config.toml" || true
else
  echo "  skipped — Homebrew is not installed."
fi

echo ""
echo "🪝 Enabling the pre-push lint/test hook..."
git -C "$DOTFILES" config core.hooksPath hooks

echo ""
if [ "$bundle_rc" -eq 0 ]; then
  echo "✅ Dotfiles are in place. Run macconfig (or ./macconfig-check.sh) any time to verify."
elif [ "$bundle_rc" -eq 1 ]; then
  echo "⚠️  Dotfiles are in place. The Brewfile entries named above are still missing."
  echo "    For anything still missing, run brewsync."
elif [ "$bundle_rc" -eq 2 ]; then
  echo "⚠️  Dotfiles are in place, but Homebrew install did not start. The reason is above."
  echo "    Fix that, then run brewsync (or run this script again)."
else
  echo "⚠️  Dotfiles are in place, but the Brewfile install failed before it could finish."
  if [ -n "${DOTFILES_LOG_FILE:-}" ]; then
    echo "    No missing package was named above. The log is ${DOTFILES_LOG_FILE}"
  else
    echo "    No missing package was named above. The log is under ~/Library/Logs/dotfiles/."
  fi
  echo "    Fix that, then run brewsync (or run this script again)."
fi

# ---- manual steps -------------------------------------------------------
# Permissions, sign-ins and settings no script can do, from lib/manual-steps.list.
# Under bootstrap.sh (DOTFILES_BOOTSTRAP=1) they're shown once at the very end instead.
MANUAL_STEPS="$DOTFILES/scripts/manual-steps.sh"
if [ "${DOTFILES_BOOTSTRAP:-0}" = 1 ]; then
  echo "   Manual steps (permissions, sign-ins) are listed when bootstrap.sh finishes."
else
  echo "   Remaining setup (login shell, hostname, Dock, defaults) is in docs/setup.md,"
  echo "   or run ./bootstrap.sh to do the whole sequence."
  echo ""
  "$MANUAL_STEPS" list || true
  if dotfiles_is_interactive; then
    echo ""
    printf 'Walk through the manual steps now, opening each settings page? [y/N] '
    read -r reply || reply=''
    case "$reply" in
      y|Y|yes|YES) "$MANUAL_STEPS" open || true ;;
      *) echo "Later: manualsteps open" ;;
    esac
  fi
fi
