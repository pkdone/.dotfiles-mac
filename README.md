# dotfiles-mac

Personal macOS dotfiles and bootstrap setup.

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

After running, trust the `mise` config to silence its warnings:

```bash
mise trust ~/.dotfiles-mac/mise/config.toml
```

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

## Set Hostname

```bash
sudo scutil --set HostName pdone-mac
sudo scutil --set LocalHostName pdone-mac
sudo scutil --set ComputerName pdone-mac
dscacheutil -flushcache
```

## Manual macOS tweaks

These System Settings adjustments aren't automated — apply them by hand on a fresh machine to match this setup.

| Area | Setting | Value |
|------|---------|-------|
| Apple Account | ID | pkdone.apple@icloud.com |
| Appearance | Theme | Dark mode |
| Displays | Built-in Display | More Space | 
| Dock | Icon size | Smaller than default (~46px) |
| Dock | Show recent applications | Off |
| Sound | Play feedback when sound is changed | On |
| Finder | Default view | Icon view |
| Finder | Show hard drives on Desktop | Off |
| Keyboard | Text input sources | British |
| Mouse | Tracking speed | faster |
| Mouse | Double click speed | faster |
| Mouse | Scrolling speed | faster |
| Trackpad | Point & click tracking speed | Slower |
| Trackpad | Point & click - click | Light |
| Trackpad | Point & Click - Lookup & Data Detectors | off |
| Trackpad | Point & Click - Secondary click | Click in bottom right corner |
| User & Groups | Paul Done icon | Dog |
