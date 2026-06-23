# Personal macOS dotfiles — task runner.
# `just` (no args) lists recipes; `just <name>` runs one. See the README for details.

# Show available recipes
default:
    @just --list

# Guided full setup: install -> shell -> hostname -> macos -> dock (pass --dry-run / --yes)
bootstrap *args:
    ./bootstrap.sh {{args}}

# Symlinks, Brewfile, and mise trust only
install:
    ./install.sh

# Read-only check that the machine still matches the repo (drift detector)
check:
    ./check.sh

# Apply the managed macOS defaults (pass --dry-run / --list)
apply *args:
    ./macos.sh {{args}}

# Pin the Dock apps in order (pass --list to preview)
dock *args:
    ./dock.sh {{args}}

# Make fish the login shell
shell:
    ./shell.sh

# Set HostName / LocalHostName / ComputerName
hostname:
    ./hostname.sh

# Install/upgrade/clean Homebrew from the Brewfile (brewsync)
sync:
    fish -c brewsync

# Run brew's own health check
doctor:
    brew doctor

# Lint shell + fish (mirrors CI and the pre-push hook)
lint:
    #!/usr/bin/env bash
    set -uo pipefail
    find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 shellcheck
    find . -name '*.fish' -not -path './.git/*' -print0 | xargs -0 -n1 fish -n
    echo "lint OK"

# Run the lib unit tests
test:
    ./tests/defaults-lib.test.sh

# Commit all changes and push: just push "message"
push msg:
    fish -c 'dotpush "{{msg}}"'
