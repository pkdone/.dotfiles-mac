function brewsync --description "Install, update, and clean up Homebrew packages"
    # Don't let brew try to upgrade casks that update themselves (auto_updates true,
    # e.g. chatgpt, docker-desktop, raycast). Those upgrades are redundant and can fail
    # messily (stale Caskroom, /Applications permission errors). Self-updating apps stay
    # current on their own; force one with `brew upgrade --greedy <cask>` if ever needed.
    set -lx HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS 1

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
    brew bundle check --file ~/.dotfiles-mac/Brewfile

    echo ""
    echo "🎉 Done! Everything is fresh."
end
