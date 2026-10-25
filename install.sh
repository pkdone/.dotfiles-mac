#!/usr/bin/env bash
#
# install.sh — bootstrap this machine: symlink configs into ~/.config, install the
# Brewfile, and trust the mise config. Login shell, hostname, macOS defaults and the
# Dock are separate scripts; bootstrap.sh runs the whole sequence in order. Ends by
# printing the manual steps (lib/manual-steps.list) and, on a terminal, offering to
# walk through them.
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
# missing. Do not run this script as root.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/dotfiles-log.sh disable=SC1091
. "$SCRIPT_DIR/lib/dotfiles-log.sh"
dotfiles_refuse_root "install.sh"

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
elif [ "$bundle_rc" -ge 2 ]; then
  echo "⚠️  Dotfiles are in place, but Homebrew install did not start. The reason is above."
  echo "    Fix that, then run brewsync (or run this script again)."
else
  echo "⚠️  Dotfiles are in place. The Brewfile entries named above are still missing."
  echo "    For anything still missing, run brewsync."
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
      *) echo "Later: $MANUAL_STEPS open" ;;
    esac
  fi
fi
