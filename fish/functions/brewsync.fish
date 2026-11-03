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

    if test (id -u) -eq 0
        echo "brewsync: refusing to run as root. Run it as your user account. It will ask for an admin password if an installer needs one." >&2
        return 1
    end

    # The body below is piped through tee, so brew-bundle-install.sh's stdout
    # is not a terminal. Record the real one first, the same way install.sh's
    # log wrapper does, or an admin-password prompt is skipped.
    #
    # `set -l` inside `if` is local to that block and is erased when the block
    # ends. `set -lx` in each branch never reached the bash script, and the
    # script then saw a pipe for stdout and reported "not a terminal" in
    # Ghostty. Function scope survives the block, is exported to the script,
    # and is gone when brewsync returns.
    set -fx DOTFILES_INTERACTIVE 0
    if isatty stdin; and isatty stdout
        set DOTFILES_INTERACTIVE 1
    end

    set -l lib "$HOME/.dotfiles-mac/lib/dotfiles-log.sh"
    # Errors from the helper (refusing a log inside the repo) stay on stderr.
    # A failed helper prints no path.
    set -l logfile (bash -c 'source "$1" && dotfiles_new_log brewsync' _ "$lib")
    if test -z "$logfile"
        return 1
    end

    begin
        __brewsync_body "$logfile"
    end 2>&1 | tee -a "$logfile"
    set -l rc $pipestatus[1]
    echo "Log: $logfile" | tee -a "$logfile"
    return $rc
end

function __brewsync_body
    set -l logfile $argv[1]
    echo "📦 Bundling from Brewfile..."
    ~/.dotfiles-mac/scripts/brew-bundle-install.sh --file ~/.dotfiles-mac/Brewfile
    set -l bundle_rc $status
    # 2: network, disk, Command Line Tools, or Homebrew itself.
    # Upgrading would hit the same wall, so stop after the message above.
    if test $bundle_rc -eq 2
        echo "Skipping upgrade and cleanup because the checks above failed."
        return $bundle_rc
    end
    # 3 and above: the installer stopped before it could name missing packages
    # (a shell error such as an unset variable). Say so, name the log, and
    # still upgrade and clean up. Exit non-zero at the end.
    if test $bundle_rc -ge 3
        echo "⚠️  The Brewfile install failed before it could finish. No missing package was named."
        echo "    The log for this run is $logfile"
    end

    echo ""
    echo "⬆️  Updating & upgrading..."
    brew update; and brew upgrade

    echo ""
    echo "🧹 Cleaning up..."
    brew cleanup

    echo ""
    echo "🔬 Removing unused dependencies..."
    brew autoremove

    echo ""
    echo "🩺 Running doctor..."
    brew doctor

    if test $bundle_rc -ge 3
        echo ""
        echo "⚠️  The Brewfile install failed before it could finish. The log is $logfile"
        return $bundle_rc
    end

    if test $bundle_rc -ne 0
        echo ""
        echo "⚠️  Some Brewfile entries are still missing. The names and the fix commands are above."
        return $bundle_rc
    end

    echo ""
    echo "🎉 Done! Everything is fresh."
end
