# dotfiles-mac

Personal macOS dotfiles and bootstrap setup.

## Setup

Do these two parts once on a new Mac, in order.

### 1. Bootstrap

Paste this block. It installs Homebrew and the GitHub CLI, signs you in to GitHub, clones this repo to `~/.dotfiles-mac`, and then runs the guided setup (`bootstrap.sh`), which asks before each step. It's safe to paste again later, or to re-run `~/.dotfiles-mac/bootstrap.sh`, because it skips anything that's already done.

```bash
command -v brew >/dev/null 2>&1 || {
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
}
brew install gh
gh auth status || gh auth login
[ -d ~/.dotfiles-mac ] || gh repo clone pkdone/.dotfiles-mac ~/.dotfiles-mac
~/.dotfiles-mac/bootstrap.sh
```

What `bootstrap.sh` sets up, step by step, is in [Setup](docs/setup.md).

### 2. Manual steps

43 settings have to be set by hand: privacy permissions, sign-ins, company-managed apps and a few System Settings pages. `macconfig` checks most of them for you afterwards; 14 you confirm by eye. Go through them once the bootstrap finishes (it prints the list and offers to walk you through it).

These are three ways to use the same checklist. You don't need to run all of them. Most of the time, `manualsteps open` is the only one you need.

```bash
manualsteps        # check each step and report whether it is done (ok), needs attention (warn), or must be checked by hand. Changes nothing.
manualsteps open   # go through each step not yet done, opening the right settings page for you
manualsteps list   # just print the full numbered checklist
```

The full checklist, and how to add a step, is in [Manual steps](docs/manual-steps.md).

<!-- BEGIN app-sources -->
## Where apps come from

This repo installs apps and tools from three places.

### Homebrew

Command-line tools and desktop apps listed in the Brewfile. The first setup installs them with `brew bundle`. After that, `brewsync` installs anything missing and upgrades what is already there. If one of these is missing, run `brewsync`.

**Command-line tools:** git, gh, fish, mise, jq, yq, ripgrep, fd, fzf, bat, eza, tree, wget, curl, direnv, tmux, htop, mas, dockutil, duti, ykman, ffmpeg, pkgconf, shellcheck, openssl, python, uv, go, rustup, mongosh, pnpm, awscli, kubernetes-cli, helm, sops, age, coreutils, findutils, gnu-sed, gawk, and grep.

**Desktop apps:** ghostty, visual-studio-code, cursor, cursor-cli, coteditor, karabiner-elements, hammerspoon, microsoft-teams, raycast, 1password-cli, logi-options+, chatgpt, claude, google-gemini, grok-bot, grok-build, google-chrome, spotify, sonos, granola, slack, whatsapp, acorn, docker-desktop, multipass, cog-app, kid3, and yubico-authenticator.

### Mac App Store

No apps currently come from the Mac App Store. This Mac can't sign in with a personal Apple ID.

### Company apps (Iru Self Service)

Company-managed apps. Install each one yourself from Iru Self Service (Kandji). The names are in `lib/mdm-apps.list`. They are not in the Brewfile. If one of these is missing, install it from Iru Self Service.

**Apps:** Okta Verify, 1Password, Tailscale, Zoom, Formal, and Cyberhaven.

1Password for Safari and Okta Extension App are not in any of these lists. This Mac can't sign in to the App Store with a personal Apple ID, and it isn't known whether Iru installs those Safari extensions. They are left out so a missing copy does not raise a warning.

Cursor Nightly and YouTube Music are installed by hand. They are not Homebrew apps and not company apps. See [Setup](docs/setup.md#apps-not-in-the-brewfile).
<!-- END app-sources -->

## Everyday commands

### macconfig

`macconfig` checks this Mac against the repo, and can put back settings that have drifted. Run it when you want that check, and after a macOS update.

```bash
macconfig          # check this Mac against the repo (read-only, changes nothing)
macconfig --fix    # check, fix anything that's safe to fix automatically, then check again
```

`macconfig --fix` only changes settings it can safely put back on its own. Anything else is listed under "Needs Paul" for you to do by hand.

What the check's output means, including the Mac health summary at the end, is explained in [Verifying the setup](docs/setup.md#verifying-the-setup).

### brewsync

`brewsync` installs, upgrades and cleans up Homebrew packages from the Brewfile. Run it after you change the Brewfile, or when a package is out of date.

```bash
brewsync           # install, upgrade and clean up Homebrew packages from the Brewfile
```

## Docs

- [Setup](docs/setup.md) — full setup walkthrough
- [Settings](docs/settings.md) — what each managed setting does and why
- [Manual steps](docs/manual-steps.md) — by-hand checklist (`lib/manual-steps.list`)
- [Troubleshooting](docs/troubleshooting.md) — after a software update, hotkey pins, sleep on mains power
- [Modes](docs/modes.md) — Hammerspoon modes
- [Shortcuts](SHORTCUTS.md) — keyboard-shortcut cheat-sheets
