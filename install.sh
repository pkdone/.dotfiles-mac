#!/usr/bin/env bash
#
# install.sh — bootstrap this machine: symlink configs into ~/.config, install the
# Brewfile, trust the mise config, and optionally set the login shell + hostname.
#
# Safe to re-run. Existing correct symlinks are repointed harmlessly; if a *real*
# file is ever in the way of a symlink, it's moved into backups/pre-symlink-<ts>/
# rather than clobbered.
#
set -euo pipefail

DOTFILES="$HOME/.dotfiles-mac"

# Fail early with a clear message if a required data file is missing.
require_file() { [ -r "$1" ] || { echo "Error: required file not found: $1" >&2; exit 1; }; }

# ---- preflight ----------------------------------------------------------
# Surface must-do-by-hand things up front as warnings, so later steps don't fail
# cryptically.
if [ "$(uname -s)" != Darwin ]; then
  echo "install.sh is for macOS (Darwin); detected $(uname -s). Aborting." >&2
  exit 1
fi

if command -v gh >/dev/null 2>&1 && ! gh auth status >/dev/null 2>&1; then
  echo "⚠️  gh is installed but not authenticated — run 'gh auth login' if you need private repos."
fi

echo "ℹ️  The Brewfile's 'mas' app (WhatsApp) requires you to be signed in to the App Store,"
echo "    or that one step will fail. Everything else will still install."

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
  if [ ! -L "$dst" ] && [ -e "$dst" ]; then
    ensure_backup_dir
    mv "$dst" "$BACKUP_DIR/"
    echo "  backed up existing $dst -> $BACKUP_DIR/"
  fi
  ln -sf "$src" "$dst"
  echo "  linked $dst"
}

echo ""
echo "🔗 Creating symlinks..."
require_file "$DOTFILES/lib/links.list"
# Static one-to-one links live in lib/links.list (shared with check.sh).
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
echo "🍺 Installing from Brewfile..."
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found — installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
brew bundle --file "$DOTFILES/Brewfile"

echo ""
echo "🔧 Trusting mise config..."
"$(brew --prefix)/bin/mise" trust "$DOTFILES/mise/config.toml" || true

echo ""
echo "✅ Dotfiles are in place. Run ./check.sh any time to verify."
echo "   Remaining setup steps (login shell, hostname, manual tweaks) are in the README."
