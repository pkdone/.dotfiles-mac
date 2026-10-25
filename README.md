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

Each run of `bootstrap.sh` and `install.sh` writes a log under `~/Library/Logs/dotfiles/` (for example `install-20260101-120000.log`) and prints that path when it finishes. Logs older than 30 days are removed. A failed Homebrew app is retried once and does not stop the others. Setup then names anything still missing and the command to install it. If that install step itself stops before it can name a package, setup says the Brewfile install failed and points at the log. An app that is already in `/Applications` is adopted instead of failing. In a terminal, setup asks once for an admin password when a package installer needs it. It stops early, with a plain explanation, if the network, the Xcode Command Line Tools, or free disk space is not ready.

### 2. Manual steps

About 40 manual steps have to be set by hand: privacy permissions, sign-ins, company-managed apps and a few System Settings pages. `macconfig` checks most of them for you afterwards; about 10 you confirm by eye. Go through them once the bootstrap finishes (it prints the list and offers to walk you through it).

These are three ways to use the same checklist. You don't need to run all of them. Most of the time, `manualsteps open` is the only one you need.

```bash
manualsteps        # check each step and report whether it is done (ok), needs attention (warn), or must be checked by hand. Changes nothing.
manualsteps open   # go through each step not yet done, opening the right settings page for you
manualsteps list   # just print the full numbered checklist (even for those already set)
```

The full checklist, and how to add a step, is in [Manual steps](docs/manual-steps.md).

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

`brewsync` installs, upgrades and cleans up Homebrew packages from the Brewfile. It retries a missing entry once, adopts an app that is already in `/Applications`, and writes a log under `~/Library/Logs/dotfiles/`. If that install step stops before it can name a package, `brewsync` says so and prints the log path, then still upgrades and cleans up, and exits with an error. Run it after you change the Brewfile, or when a package is out of date.

```bash
brewsync           # install, upgrade and clean up Homebrew packages from the Brewfile
```

## Where apps come from

<!-- BEGIN app-sources -->
Apps and tools come from three places:
1. Homebrew, via the Brewfile, for most apps and command-line tools.
2. Fleet Self service, for company-managed apps that can't be installed unattended. Setup prompts you to install them.
3. The Mac App Store. Nothing is installed from it now, because this Mac can't sign in with a personal Apple ID.
<!-- END app-sources -->

## Docs

- [Setup](docs/setup.md) — full setup walkthrough
- [Settings](docs/settings.md) — what each managed setting does and why
- [Manual steps](docs/manual-steps.md) — by-hand checklist (`lib/manual-steps.list`)
- [Troubleshooting](docs/troubleshooting.md) — after a software update, hotkey pins, sleep on mains power
- [Modes](docs/modes.md) — Hammerspoon modes
- [Shortcuts](SHORTCUTS.md) — keyboard-shortcut cheat-sheets
