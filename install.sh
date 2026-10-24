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

# shellcheck source=lib/join-names.sh disable=SC1091
. "$DOTFILES/lib/join-names.sh"
mas_apps="$(sed -nE 's/^mas "([^"]+)".*/\1/p' "$DOTFILES/Brewfile" | join_and)"
if [ -n "$mas_apps" ]; then
  echo "ℹ️  Mac App Store apps in the Brewfile (${mas_apps}) need App Store sign-in."
  echo "    If you are not signed in, those installs fail. Homebrew packages still install."
else
  echo "ℹ️  The Brewfile has no Mac App Store apps."
fi
echo "    Anything from Homebrew that is still missing: run brewsync."

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
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found — installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# Tolerate a partial failure (e.g. a Mac App Store app such as Keynote when not
# signed in to the App Store): brew bundle attempts every entry, so we record
# the outcome and carry on to mise trust + the summary rather than letting
# set -e abort the whole bootstrap.
# On a terminal, a failed `brew bundle check` opens the App Store, asks Paul to sign
# in, and retries `brew bundle install` once. Non-interactive runs keep the warning
# below. Sign-in is the App Store UI; the mas CLI is not consulted.
bundle_ok=1
brew bundle --file "$DOTFILES/Brewfile" || bundle_ok=0
if brew bundle check --file "$DOTFILES/Brewfile" >/dev/null 2>&1; then
  bundle_ok=1
elif [ -t 0 ]; then
  echo ""
  echo "⚠️  Some Brewfile entries are still missing."
  echo "    Homebrew packages: run brewsync. Mac App Store apps: needs App Store sign-in."
  brew bundle check --file "$DOTFILES/Brewfile" --verbose 2>&1 | sed 's/^/    /' || true
  echo "    Opening the App Store. Sign in, then this retries the install once."
  open 'macappstore://' || echo "    (couldn't open macappstore:// — open the App Store and sign in)"
  printf 'Sign in to the App Store, then press Enter to retry brew bundle once: '
  read -r _ || true
  echo "Retrying brew bundle install once..."
  brew bundle install --file "$DOTFILES/Brewfile" || true
  if brew bundle check --file "$DOTFILES/Brewfile" >/dev/null 2>&1; then
    bundle_ok=1
  else
    bundle_ok=0
  fi
else
  bundle_ok=0
fi

echo ""
echo "🔧 Trusting mise config..."
"$(brew --prefix)/bin/mise" trust "$DOTFILES/mise/config.toml" || true

echo ""
echo "🪝 Enabling the pre-push lint/test hook..."
git -C "$DOTFILES" config core.hooksPath hooks

echo ""
if [ "$bundle_ok" = 1 ]; then
  echo "✅ Dotfiles are in place. Run macconfig (or ./macconfig-check.sh) any time to verify."
else
  echo "⚠️  Dotfiles are in place, but some Brewfile entries did not install."
  echo "    Homebrew packages: run brewsync. Mac App Store apps: needs App Store sign-in."
  echo "    Then re-run, or run: brew bundle check --file \"$DOTFILES/Brewfile\""
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
  if [ -t 0 ] && [ -t 1 ]; then
    echo ""
    printf 'Walk through the manual steps now, opening each settings page? [y/N] '
    read -r reply || reply=''
    case "$reply" in
      y|Y|yes|YES) "$MANUAL_STEPS" open || true ;;
      *) echo "Later: $MANUAL_STEPS open" ;;
    esac
  fi
fi
