function manualsteps --description "Check or walk through the settings you do by hand"
    # Same location install.sh and brewsync use ($HOME/.dotfiles-mac).
    # scripts/manual-steps.sh finds its files from its own path, so this leaves the
    # caller's working directory alone. No arguments means check.
    set -l repo $HOME/.dotfiles-mac
    set -l args $argv
    if test (count $args) -eq 0
        set args check
    end
    "$repo/scripts/manual-steps.sh" $args
end
