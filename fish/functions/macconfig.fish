function macconfig --description "Check this Mac's config settings against the dotfiles repo"
    # Same location install.sh and brewsync use ($HOME/.dotfiles-mac).
    # macconfig-check.sh finds its files from its own path, so this leaves the
    # caller's working directory alone. Arguments pass through, including
    # --only area[,area], --fix, --no-color, --health-json, and
    # --reset-folder-views [--dry-run].
    set -l repo $HOME/.dotfiles-mac
    "$repo/macconfig-check.sh" $argv
end
