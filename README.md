# dotfiles-mac

Personal macOS dotfiles for fish, ghostty, and Homebrew.

## Contents

- `Brewfile` — all Homebrew packages and casks
- `fish/` — fish shell config and functions
- `ghostty/` — ghostty terminal config
- `gitconfig` — Git user and behaviour settings
- `mise/` — pinned default tool versions (Node, npm)
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

## Manual macOS tweaks

These System Settings adjustments aren't automated — apply them by hand on a fresh machine to match this setup.

| Area | Setting | Value |
|------|---------|-------|
| Appearance | Theme | Dark mode |
| Dock | Icon size | Smaller than default (~46px) |
| Dock | Show recent applications | Off |
| Finder | Default view | Icon view |
| Finder | Show hard drives on Desktop | Off |
