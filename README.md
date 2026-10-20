# dotfiles-mac

Personal macOS dotfiles and bootstrap setup.

## Setup

On a fresh Mac, paste this block. It installs Homebrew when `brew` is not already on PATH (the official installer, then `brew shellenv` for Apple Silicon), installs the GitHub CLI, signs in when `gh auth status` is not already ok, clones this private repo when `~/.dotfiles-mac` does not exist, and runs the guided bootstrap. Paste it again later: each of those steps skips work that is already done. Bootstrap walks through `install.sh`, `shell.sh`, `hostname.sh`, `macos.sh`, `dock.sh`, `handlers.sh`, and `prune-apps.sh`, prompting before each. It is safe to re-run. `--yes` skips the prompts; `--dry-run` previews every step.

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

## Commands

| Command | What it does |
|------|------|
| `macconfig` | Checks this Mac's config settings against the repo (`macconfig-check.sh`). Arguments pass through: `macconfig`, `macconfig --fix`, `macconfig --no-color` |
| `check.sh` | Shim that execs `macconfig-check.sh` with the same arguments, stdin, and exit status. Kept so existing callers (the scheduled `~/.dotfiles-mac/check.sh --fix --no-color`, plus muscle memory) stay valid. |
| `--fix` | `macconfig-check.sh` on its own never changes anything. `--fix` repairs only the drift that is classed SAFE, re-checks, and lists Fixed / Needs Paul. |
| `brewsync` | Installs, upgrades, and cleans up Homebrew packages from the Brewfile. Sets `HOMEBREW_NO_ASK` for that run only, so Homebrew 7 does not ask "Do you want to proceed?"; a hand-typed `brew upgrade` still asks |

```bash
macconfig          # check this Mac against the repo (read-only)
macconfig --fix    # check, repair safe drift, then re-check
brewsync           # install, upgrade and clean up Homebrew packages from the Brewfile
```

The summary, the SAFE / Needs Paul split, and the Mac health signals are in [Setup](docs/setup.md#verifying-the-setup).

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
