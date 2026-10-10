function brewsync --description "Install, update, and clean up Homebrew packages"
    # Don't let brew try to upgrade casks that update themselves (auto_updates true,
    # e.g. chatgpt, docker-desktop, raycast). Those upgrades are redundant and can fail
    # messily (stale Caskroom, /Applications permission errors). Self-updating apps stay
    # current on their own; force one with `brew upgrade --greedy <cask>` if ever needed.
    set -lx HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS 1

    # Homebrew 7 asks before install/upgrade ("Do you want to proceed with the
    # upgrade? [y/n]"). Opt out for this function only, so brewsync (including
    # the unattended `fish -c brewsync </dev/null` job) never stops on that
    # prompt, while a hand-typed `brew upgrade` still asks. `brew bundle`
    # installs through `brew install`, which honors the same variable.
    # `brew autoremove`, `brew cleanup`, `brew doctor`, and `brew bundle check`
    # do not prompt.
    set -lx HOMEBREW_NO_ASK 1

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
