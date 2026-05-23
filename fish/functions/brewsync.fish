function brewsync --description "Install, update, and clean up Homebrew packages"
    echo "📦 Bundling from Brewfile..."
    brew bundle --file ~/.dotfiles-mac/Brewfile

    echo ""
    echo "⬆️  Updating & upgrading..."
    brew update && brew upgrade

    echo ""
    echo "🧹 Cleaning up..."
    brew cleanup

    echo ""
    echo "🔬 Removing unused dependencies..."
    brew autoremove

    echo ""
    echo "🩺 Running doctor..."
    brew doctor

    echo ""
    echo "✅ Checking bundle..."
    brew bundle check --file ~/dotfiles/Brewfile

    echo ""
    echo "🎉 Done! Everything is fresh."
end
