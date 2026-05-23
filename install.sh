#!/bin/bash
set -e

DOTFILES="$HOME/.dotfiles-mac"

echo "🔗 Creating symlinks..."

# Ghostty
mkdir -p "$HOME/.config/ghostty"
ln -sf "$DOTFILES/ghostty/config" "$HOME/.config/ghostty/config"

# Fish
mkdir -p "$HOME/.config/fish/functions" "$HOME/.config/fish/conf.d"
ln -sf "$DOTFILES/fish/config.fish" "$HOME/.config/fish/config.fish"
ln -sf "$DOTFILES/fish/functions/brewsync.fish" "$HOME/.config/fish/functions/brewsync.fish"
ln -sf "$DOTFILES/fish/functions/edit.fish" "$HOME/.config/fish/functions/edit.fish"
ln -sf "$DOTFILES/fish/functions/dotpush.fish" "$HOME/.config/fish/functions/dotpush.fish"

echo ""
echo "🍺 Installing from Brewfile..."
if ! command -v brew &>/dev/null; then
  echo "Homebrew not found — installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
brew bundle --file "$DOTFILES/Brewfile"

echo ""
echo "✅ Done! Dotfiles are in place."
