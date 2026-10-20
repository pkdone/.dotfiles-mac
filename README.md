# dotfiles-mac

Personal macOS dotfiles and bootstrap setup.

## Setup

On a fresh Mac, paste this block. It installs Homebrew and the GitHub CLI, signs you in to GitHub, clones this repo to `~/.dotfiles-mac`, and then runs the guided setup, which asks before each step. It's safe to paste again later, because it skips anything that's already done.

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

The walkthrough after that paste — dotfiles, the apps Homebrew can't install, shell, hostname, Dock, handlers, and the checks — is in [Setup](docs/setup.md).

## Everyday commands

```bash
macconfig          # check this Mac against the repo (read-only, changes nothing)
macconfig --fix    # check, fix anything that's safe to fix automatically, then check again
brewsync           # install, upgrade and clean up Homebrew packages from the Brewfile
```

`macconfig --fix` only changes settings it can safely put back on its own. Anything else is listed under "Needs Paul" for you to do by hand. `check.sh` is an older name for `macconfig`, kept because the scheduled morning check still calls it.

What the check's output means, including the Mac health summary at the end, is explained in [Verifying the setup](docs/setup.md#verifying-the-setup).

## Manual steps

About 35 settings can't be scripted: privacy permissions, sign-ins, company MDM apps and a few System Settings pages. Go through them once on a new Mac after the bootstrap finishes (it prints the list and offers to walk you through it), and again after a macOS update or whenever `macconfig` shows a manual step as warn.

```bash
~/.dotfiles-mac/scripts/manual-steps.sh list    # numbered checklist
~/.dotfiles-mac/scripts/manual-steps.sh open    # walk through the steps not yet done
~/.dotfiles-mac/scripts/manual-steps.sh check   # read-only: ok / warn / by hand
```

The full checklist, and how to add a step, is in [Manual steps](docs/manual-steps.md).

## Docs

- [Setup](docs/setup.md) — full setup walkthrough
- [Settings](docs/settings.md) — what each managed setting does and why
- [Manual steps](docs/manual-steps.md) — by-hand checklist (`lib/manual-steps.list`)
- [Troubleshooting](docs/troubleshooting.md) — after a software update, hotkey pins, AC sleep
- [Modes](docs/modes.md) — Hammerspoon modes
- [Shortcuts](SHORTCUTS.md) — keyboard-shortcut cheat-sheets
