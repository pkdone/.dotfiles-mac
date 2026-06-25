# dotfiles-mac

Personal macOS dotfiles and bootstrap setup.

## Contents

- `Brewfile` — all Homebrew packages and casks
- `fish/` — Fish shell config and functions
- `ghostty/` — Ghostty terminal config
- `gitconfig` — Git user and behaviour settings
- `mise/` — pinned default tool versions (Node, npm)
- `lib/` — shared data the scripts read: `macos-defaults.list`, `dock-apps.list`, `links.list`, `hostname`, and `defaults-lib.sh` (comparison helpers)
- `bootstrap.sh` — guided full setup: runs install/shell/hostname/macos/dock in order (idempotent)
- `install.sh` — bootstraps a new machine (symlinks, Brewfile, mise)
- `macos.sh` — applies a curated set of macOS `defaults` (idempotent)
- `dock.sh` — pins the Dock apps in order (idempotent; needs dockutil)
- `shell.sh` — makes fish the login shell (idempotent)
- `hostname.sh` — sets the host names (idempotent)
- `check.sh` — read-only check that the machine still matches the repo (drift detector)
- `defaults-diff.sh` — discover which `defaults` key backs a System Settings toggle
- `tests/` — plain-bash unit tests for the shared `lib/` helpers
- `hooks/` — git hooks (pre-push lint/test gate), enabled via `core.hooksPath`
- `Justfile` — task runner wrapping the scripts (`just --list`)
- `SHORTCUTS.md` — keyboard-shortcut & macOS reference cheat-sheets

## Setup

### Bootstrap

On a fresh machine, first install Homebrew (which also pulls in the Command Line Tools that provide `git`), then the GitHub CLI, and sign in — this is what lets the private repo be cloned over HTTPS:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install gh
gh auth login
```

Clone the repo:

```bash
git clone https://github.com/pkdone/.dotfiles-mac.git ~/.dotfiles-mac
```

Then run the guided bootstrap. It walks through every step in order (`install.sh` -> `shell.sh` -> `hostname.sh` -> `macos.sh` -> `dock.sh`), prompting before each, and is idempotent so it's safe to re-run:

```bash
~/.dotfiles-mac/bootstrap.sh --dry-run   # preview every step, change nothing
~/.dotfiles-mac/bootstrap.sh             # run it (prompts before each; --yes skips prompts)
```

`install.sh` is the first step `bootstrap.sh` runs, and you can also run it on its own to set up just the dotfiles layer:

- **Preflight** — confirms you're on macOS, warns if `gh` is unauthenticated, and notes the App Store sign-in the `mas` app needs.
- **Symlinks** — links the configs in this repo into `~/.config` (and `~/.gitconfig`), moving any real file already in the way into `backups/pre-symlink-<timestamp>/` rather than clobbering it.
- **Brewfile + mise** — installs everything in the Brewfile (tolerating a partial failure, e.g. the App Store app when you're not signed in), then trusts the `mise` config.
- **Pre-push hook** — points `core.hooksPath` at `hooks/` so the local lint/test gate is active.

It does **not** set your login shell, hostname, macOS defaults or Dock — those are the separate scripts documented below, which `bootstrap.sh` runs in turn. Each can also be run on its own.

### Apps not in the Brewfile

> _Manual — no script installs these; do them by hand._

Two apps can't be installed by `brew bundle`, so set them up by hand after bootstrapping:

- **Cursor Nightly** — download and install it manually from the [Cursor Nightly download page](https://cursor.com/nightlydownload), as a separate app. It's deliberately kept out of the Brewfile (which installs only the stable Cursor), so the stable build and Nightly sit side by side.
- **YouTube Music** — a Chrome PWA. In Chrome, open `music.youtube.com`, then click the install icon in the address bar (or **⋮ menu → Cast, save, and share → Install page as app**).

Do both before running `dock.sh`, or it'll skip them.

### Set login shell

> _Run by `bootstrap.sh`; the commands below run only this step (not part of `install.sh`)._

Make Fish (installed by the Brewfile) your login shell. `shell.sh` adds it to `/etc/shells` and runs `chsh` for you — idempotent, and it prompts for your password (sudo) only if a change is actually needed:

```bash
~/.dotfiles-mac/shell.sh --dry-run   # preview
~/.dotfiles-mac/shell.sh             # apply
```

### Set Hostname

> _Run by `bootstrap.sh`; the commands below run only this step (not part of `install.sh`)._

`hostname.sh` sets HostName, LocalHostName and ComputerName (idempotent; uses sudo only when a name actually differs, and flushes the DNS cache only if something changed):

```bash
~/.dotfiles-mac/hostname.sh --dry-run   # preview
~/.dotfiles-mac/hostname.sh             # apply
```

### Dock

> _Run by `bootstrap.sh` (after the manual apps above); the commands below run only this step._

Pin the apps to the Dock in order (idempotent; uses `dockutil` from the Brewfile):

```bash
~/.dotfiles-mac/dock.sh --list   # preview the apps and their order
~/.dotfiles-mac/dock.sh          # apply
```

### macOS defaults

> _Run by `bootstrap.sh`; the commands below run only this step (not part of `install.sh`)._

A curated set of macOS `defaults` is applied by `macos.sh`:

```bash
~/.dotfiles-mac/macos.sh --dry-run   # preview every decision, write nothing
~/.dotfiles-mac/macos.sh             # apply
```

Safe to re-run: it reads and type-checks each setting first, then writes the desired value (re-asserting even when it already matches), skips any key whose stored type is unexpected (with a warning), and sets missing keys. Before the first actual change it backs up each affected domain to `backups/defaults-<timestamp>/`. UI restarts (Dock, Finder, menu bar) happen at the end only when something actually changed, after you confirm.

Run `macos.sh --list` to see the exact set of settings it manages (printed as a Markdown table).

### Verifying the setup

> _Standalone tool — not run by `bootstrap.sh`; run it whenever you want to check for drift._

`check.sh` is a read-only check that this machine still matches the repo — symlinks, Brewfile, every managed `defaults` key, the Dock, login shell, and hostname. It changes nothing and exits non-zero if it finds drift (handy after a macOS update silently resets something):

```bash
~/.dotfiles-mac/check.sh
```

### Discovering new defaults

> _Standalone dev workflow — not part of setup._

To find which `defaults` key backs a System Settings toggle (so you can add it to `lib/macos-defaults.list`), use `defaults-diff.sh`. It compares a before/after pair, so you must actually change the setting in System Settings between the two snapshots — otherwise the snapshots are identical and `diff` reports nothing:

```bash
~/.dotfiles-mac/defaults-diff.sh snapshot before   # capture current state
# ...change ONE setting in System Settings...
~/.dotfiles-mac/defaults-diff.sh snapshot after    # capture again
~/.dotfiles-mac/defaults-diff.sh diff              # changed keys, as list rows
```

`diff` prints each changed/new key as a `domain|key|type|value|…` row in the exact format `lib/macos-defaults.list` expects — paste the matching one in, fill the `restart|area|label|display` columns, then run `macos.sh --dry-run` and `check.sh` to confirm. Notes:

- It scans every domain, so the diff usually includes a little unrelated churn (timestamps, recent-item lists), and each snapshot takes a minute or so. Look for the row matching what you toggled and ignore the rest.
- `cfprefsd` caches preferences, so a value you just changed may not appear until you quit and reopen System Settings (or run `killall cfprefsd`) before the `after` snapshot.
- Settings not exposed via `defaults` (private-API sliders, sudo-only, TCC-gated) won't show up — those stay in the manual list below.

### Manual macOS tweaks

The settings below aren't automated (not exposed via `defaults`, require sudo, or out of scope) — apply them by hand on a fresh machine to match this setup.

#### System Settings

| Area | Setting | Value | Reason not automated |
|------|------|------|------|
| Apple Account | ID | `<myuserid>@icloud.com` | Interactive Apple ID sign-in; not a `defaults` key |
| Displays | Built-in Display | More Space | Display scaling is hardware-specific; not reliably scriptable |
| Desktop & Dock | Widgets on desktop | None (all removed) | Widget placement isn't exposed via `defaults`; removed per-widget in the UI |
| Keyboard | Text input sources | British | Input sources are a complex array blob; error-prone to script |
| Mouse | Tracking speed | faster | Device-specific pointer scaling; left manual to preserve feel |
| Mouse | Natural scrolling | Off | Global key also flips the trackpad; handled via Logi Options+ |
| Mouse | Secondary click | Click Right Side | Button mapping stored per-device, not a stable global key |
| Mouse | Double click speed | faster | Device-specific timing; no stable global `defaults` key |
| Mouse | Scrolling speed | faster | Device-specific scaling; left manual |
| Trackpad | Point & Click tracking speed | Slower | Trackpad prefs span two interdependent domains; fragile to script |
| Trackpad | Point & Click - click | Light | Trackpad prefs span two interdependent domains; fragile to script |
| Trackpad | Point & Click - Lookup & Data Detectors | off | Trackpad prefs span two interdependent domains; fragile to script |
| Trackpad | Point & Click - Secondary click | Click in bottom right corner | Trackpad prefs span two interdependent domains; fragile to script |
| Trackpad | Point & Click - Tap to click | On | Trackpad prefs span two interdependent domains; fragile to script |
| Trackpad | Point & Click - Force Click and haptic feedback | Off | Trackpad prefs span two interdependent domains; fragile to script |
| Trackpad | More Gestures - Three-finger drag | Off | Trackpad prefs span two interdependent domains; fragile to script |
| Accessibility | Pointer Control — Trackpad Options — Use trackpad for dragging | On (Without Drag Lock) | Accessibility settings are TCC-protected; not writable via `defaults` |
| Accessibility | Display — Pointer — Pointer size | One notch above Normal | Accessibility settings are TCC-protected; not writable via `defaults` |
| User & Groups | Paul Done icon | Dog | Account picture is set via Directory Services, not `defaults` |
| Notifications | When mirroring or sharing the display | Notifications Off | Notification prefs are SIP-protected (ncprefs); unsafe to script |
| Notifications | App notifications turned Off: Calendar, Cursor Nightly, FaceTime, Game Center, Home, Mail, Microsoft Teams, Slack, Spotify, Tips, Wallet | Off | Notification prefs are SIP-protected (ncprefs); unsafe to script |
| Spotlight | Results from Apps — disable: Books, Keynote, Mail, Notes, Numbers, Photos, Podcasts, Reminders, Stocks, Tips, Voice Memos | Off | Changing categories triggers reindexing; complex ordered array, out of scope |

#### Finder

| Area | Setting | Value |
|------|------|------|
| Sidebar | Show Recents | Off |

#### CotEditor

| Area | Setting | Value |
|------|------|------|
| Mode | General - Font | Monospaced |
| Appearance | Default theme | Anura (Dark) |

#### AltTab

| Area | Setting | Value |
|------|------|------|
| Controls | Show windows from Spaces | Visible Spaces |
| Controls | Show apps with no open window | Hide |
| Exceptions | Slack | Hide windows |

#### Logi Options+

| Area | Setting | Value |
|------|------|------|
| Pointer & Scrolling | Smooth scrolling | On |

#### Gemini

The Gemini desktop app's default shortcuts (`Option + Space` and `Option + Shift + Space`) clash with the ChatGPT app. Change them via Gemini Settings → Shortcuts:

| Action | Shortcut |
|------|------|
| Mini chat | `Control + Option + G` |
| Full chat | `Control + Option + Shift + G` |

#### Raycast

On first launch, Raycast auto-binds itself to `Option + Space`, which clashes with the ChatGPT app. Change it via Raycast Settings → General → Raycast Hotkey to `Shift + Control + Command + R`.

To bind a global hotkey for activating Finder from anywhere:
1. Open Raycast (`Shift + Control + Command + R`)
2. Type **Finder** until "Finder" appears as a command result
3. Highlight it and press `Command + K` (Actions menu)
4. Choose **Configure Application…**
5. Click the **Record Hotkey** field and press `Shift + Control + Command + F`

To enable Clipboard History:
1. Open Raycast and run the **Clipboard History** command once
2. Grant Accessibility permission if prompted (System Settings → Privacy & Security → Accessibility → enable Raycast)
3. Bind a hotkey via Raycast Settings → Extensions → search "clipboard", then in the **Clipboard History** row of type **Command** (not the parent "Extension" row), click **Record Hotkey** and press `Control + Command + V`.
   - Avoid `Command + Shift + V` (paste without formatting) and `Command + Option + V` (Finder paste-as-move).
4. Set **Keep History For** to 1 Day
5. Add password apps to **Disabled Applications** so their copies are never recorded: 1Password, 1Password for Safari

## Usage & reference

### Scripts

| Script | What it does, and when to run it |
|------|------|
| `bootstrap.sh` | Guided full setup: runs `install.sh`, `shell.sh`, `hostname.sh`, `macos.sh`, `dock.sh` in order, prompting before each. `--dry-run` previews all steps, `--yes` skips prompts. Idempotent. |
| `install.sh` | The dotfiles layer of a fresh-machine setup: preflight, symlinks, Brewfile, `mise` trust, and enabling the pre-push hook. Does *not* set shell/hostname/defaults/Dock (those are `bootstrap.sh`). Safe to re-run — repoints symlinks, backs up any real file in the way. |
| `check.sh` | Read-only check that the machine still matches the repo (symlinks, Brewfile, defaults, Dock, shell, hostname). Run any time, especially after a macOS update. Changes nothing; exits non-zero on drift. |
| `macos.sh` | Apply the managed macOS `defaults`. Run after bootstrap and whenever you edit `lib/macos-defaults.list`. `--dry-run` previews, `--list` prints the table. Idempotent. |
| `dock.sh` | Pin the Dock apps in order. Run after the apps are installed and whenever you edit `lib/dock-apps.list`. `--list` previews. Idempotent; needs `dockutil`. |
| `shell.sh` | Make fish the login shell. Run once on a fresh machine (see "Set login shell"). Idempotent; sudo/`chsh` only if needed. |
| `hostname.sh` | Set HostName/LocalHostName/ComputerName. Run once on a fresh machine (see "Set Hostname"). Idempotent; sudo only if a name differs. |
| `defaults-diff.sh` | Discover which `defaults` key backs a System Settings toggle, to add to `lib/macos-defaults.list`. Run when you want to manage a new setting. Read-only. |

All scripts accept `-h`/`--help`.

### Task runner

If you'd rather not remember script names, `just` wraps them. `just --list` shows every
recipe; e.g. `just check`, `just apply`, `just sync`, `just lint`, `just test`, `just push "msg"`.

### Pre-push checks

A version-controlled git hook (`hooks/pre-push`, enabled by `install.sh` / `bootstrap.sh`
via `core.hooksPath`) mirrors the CI gates locally: before each push it runs `shellcheck`
on the shell scripts, `fish -n` on the fish files, and the `tests/` unit tests. A missing
tool is skipped rather than blocking. Bypass in a pinch with `git push --no-verify`.

### Making changes

Edit configs normally — changes go directly into the repo via symlinks. Then push:

```bash
dotpush "your message"
```

- **New packages:** add to `Brewfile`, run `brewsync`.
- **Managed macOS settings:** edit `lib/macos-defaults.list`, then run `macos.sh` (use `defaults-diff.sh` to find the key first).
- **Dock apps:** edit `lib/dock-apps.list`, then run `dock.sh`.
- After any change, run `check.sh` to confirm the machine still matches the repo.

### Fish functions

| Function | Description |
|------|------|
| `brewsync` | Installs, upgrades, and cleans up Homebrew packages from the Brewfile |
| `dotpush <message>` | Commits and pushes all dotfile changes to GitHub in one command |
| `edit <file>` | Opens a file in CotEditor |

### Keyboard shortcuts & reference

The macOS, terminal, and Ghostty keyboard-shortcut cheat-sheets now live in
[SHORTCUTS.md](SHORTCUTS.md).
