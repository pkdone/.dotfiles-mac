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

The walkthrough after that paste (dotfiles, the apps Homebrew can't install, shell, hostname, Dock, file handlers and the checks) is in [Setup](docs/setup.md).

### 2. Manual steps

About 35 settings can't be scripted: privacy permissions, sign-ins, company MDM apps and a few System Settings pages. Go through them once the bootstrap finishes (it prints the list and offers to walk you through it).

These are three ways to use the same checklist. You don't need to run all of them. Most of the time, `manualsteps open` is the only one you need.

```bash
manualsteps        # see which steps are done: ok, warn, or check by hand. Changes nothing.
manualsteps open   # go through each step not yet done, opening the right settings page for you
manualsteps list   # just print the full numbered checklist
```

The full checklist, and how to add a step, is in [Manual steps](docs/manual-steps.md).

## Everyday commands

`macconfig` checks this Mac against the repo, and puts settings back when they no longer match and the fix is safe. Run it when you want that check, and after a macOS update.

```bash
macconfig          # check this Mac against the repo (read-only, changes nothing)
macconfig --fix    # check, fix anything that's safe to fix automatically, then check again
```

`macconfig --fix` only changes settings it can safely put back on its own. Anything else is listed under "Needs Paul" for you to do by hand. `check.sh` is an older name for `macconfig`, kept because the scheduled morning check still calls it.

What the check's output means, including the Mac health summary at the end, is explained in [Verifying the setup](docs/setup.md#verifying-the-setup).

`manualsteps` is worth running again after a macOS update, or whenever `macconfig` shows a manual step as warn.

`brewsync` installs, upgrades and cleans up Homebrew packages from the Brewfile. Run it after you change the Brewfile, or when a package is out of date.

```bash
brewsync           # install, upgrade and clean up Homebrew packages from the Brewfile
```

## Docs

- [Setup](docs/setup.md) — full setup walkthrough
- [Settings](docs/settings.md) — what each managed setting does and why
- [Manual steps](docs/manual-steps.md) — by-hand checklist (`lib/manual-steps.list`)
- [Troubleshooting](docs/troubleshooting.md) — after a software update, hotkey pins, AC sleep
- [Modes](docs/modes.md) — Hammerspoon modes
- [Shortcuts](SHORTCUTS.md) — keyboard-shortcut cheat-sheets
