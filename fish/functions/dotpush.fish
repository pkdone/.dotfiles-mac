function dotpush --description "Commit and push dotfiles with a message"
    if test (count $argv) -eq 0
        echo "Usage: dotpush \"your commit message\""
        return 1
    end

    set -l dotfiles $HOME/dotfiles

    cd $dotfiles
    git add -A

    if git diff --cached --quiet
        echo "Nothing to commit — dotfiles are up to date."
        return 0
    end

    git commit -m $argv[1]
    git push
    echo "✅ Dotfiles pushed."
end
