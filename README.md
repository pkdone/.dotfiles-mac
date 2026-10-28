# dotfiles-mac

Personal macOS dotfiles and bootstrap setup.

## Setup

Do these two parts once on a new Mac, in order.

### 1. Bootstrap

Paste the first block, wait for it to finish (it may ask for the Mac password and to press Return), then paste the second block and finish signing in to GitHub. Then paste the third block. Signing in asks questions in the terminal and may open a browser, so the clone is a separate paste. The three blocks install Homebrew and the GitHub CLI, sign you in to GitHub, clone this repo to `~/.dotfiles-mac`, and then run the guided setup (`bootstrap.sh`), which asks before each step. It's safe to paste again later, or to re-run `~/.dotfiles-mac/bootstrap.sh`, because it skips anything that's already done.

```bash
command -v brew >/dev/null 2>&1 || {
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
}
```

```bash
{
  eval "$(/opt/homebrew/bin/brew shellenv)"
  brew install gh
  gh auth status || gh auth login
}
```

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
[ -d ~/.dotfiles-mac ] || gh repo clone pkdone/.dotfiles-mac ~/.dotfiles-mac
~/.dotfiles-mac/bootstrap.sh
```

What `bootstrap.sh` sets up, step by step, is in [Setup](docs/setup.md).

### 2. Manual steps

A completely fresh Mac has up to about 50 steps you set by hand: privacy permissions, sign-ins, company-managed apps, and a few System Settings pages. Usually far fewer are still open. Company device management (Fleet) covers many of them, some apps sign back in through iCloud or 1Password, and an earlier run may already have done the rest. `macconfig` checks most of them afterwards; about 15 you confirm by eye.

When `bootstrap.sh` finishes, it lists the steps still open on this Mac, including any it can't check, and offers to walk you through them. You don't need to run anything else.

To see or go through them again later, run:

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

If a Finder folder isn't sorted by name, it has saved its own view. This puts every folder in your home folder, Desktop included, back on the default view. Each folder's own view settings and icon positions are lost, and it only runs when you ask:

```bash
macconfig --reset-folder-views --dry-run   # list what it would clear; changes nothing
macconfig --reset-folder-views             # clear the saved folder views and restart Finder
```

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
