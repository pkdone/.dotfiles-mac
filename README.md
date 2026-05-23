# dotfiles-mac

Personal macOS dotfiles for fish, ghostty, and Homebrew.

## Contents

- `Brewfile` — all Homebrew packages and casks
- `fish/` — fish shell config and functions
- `ghostty/` — ghostty terminal config
- `install.sh` — bootstraps a new machine

## New machine setup

```bash
git clone https://github.com/pkdone/.dotfiles-mac.git ~/.dotfiles-mac
bash ~/.dotfiles-mac/install.sh
```

This creates symlinks from `~/.config` into this repo and installs everything in the Brewfile.

## Day-to-day

Edit configs normally — changes go directly into the repo via symlinks. Then push:

```bash
dotpush "your message"
```

To install new packages, add them to `Brewfile` and run `brewsync`.

## Fish functions

| Function | Description |
|----------|-------------|
| `brewsync` | Installs, upgrades, and cleans up Homebrew packages from the Brewfile |
| `dotpush` | Commits and pushes all dotfile changes to GitHub in one command |
| `edit` | Opens a file in CotEditor |
