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
for f in "$DOTFILES"/fish/functions/*.fish; do
  ln -sf "$f" "$HOME/.config/fish/functions/$(basename "$f")"
done

# Mise
mkdir -p "$HOME/.config/mise"
ln -sf "$DOTFILES/mise/config.toml" "$HOME/.config/mise/config.toml"

# Git
ln -sf "$DOTFILES/gitconfig" "$HOME/.gitconfig"

echo ""
echo "🍺 Installing from Brewfile..."
if ! command -v brew &>/dev/null; then
  echo "Homebrew not found — installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
brew bundle --file "$DOTFILES/Brewfile"

echo ""
echo "🔧 Trusting mise config..."
"$(brew --prefix)/bin/mise" trust "$DOTFILES/mise/config.toml" || true

echo ""
echo "✅ Done! Dotfiles are in place."
