# Homebrew
eval "$(/opt/homebrew/bin/brew shellenv)"

# Look and feel
set -g fish_greeting ""
set -g fish_cursor_default block

# Editor
set -gx EDITOR "vi"
set -gx VISUAL "coteditor --wait"
set -gx GIT_EDITOR "coteditor --wait"

# Paths
fish_add_path $HOME/.local/bin

# Auto-switches tool versions (Node, Python, etc.) per project
mise activate fish | source

# Auto-loads/unloads .envrc variables when cd-ing between projects
direnv hook fish | source

# fzf key bindings (Ctrl-R history search, Ctrl-T file finder) and completions
fzf --fish | source

# Opt out of Homebrew's phone-home anonymous usage analytics
set -gx HOMEBREW_NO_ANALYTICS 1

# Aliases
alias ll "eza -la --git"
