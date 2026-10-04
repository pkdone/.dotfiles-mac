# dotfiles-mac

Personal macOS dotfiles and bootstrap setup.

## Contents

- `Brewfile` — Homebrew packages and casks
- `fish/` — Fish shell config and functions
- `ghostty/` — Ghostty terminal config
- `karabiner/` — Karabiner-Elements config (directory-symlinked into `~/.config/karabiner`)
- `hammerspoon/` — Hammerspoon Lua automations (directory-symlinked into `~/.hammerspoon`; `init.lua` loads modules such as `sidecar_slack.lua`)
- `gitconfig` — Git user and behaviour settings
- `mise/` — pinned tool versions (Node 22)
- `lib/` — data for the scripts (`macos-defaults.list`, `dock-apps.list`, `desktop-bindings.list`, `desktop-bindings.py`, `url-handlers.list`, `unwanted-apps.list`, `links.list`, `hostname`, `finder-sidebar-recents.py`, `btm-login-items.py`, `mdm-apps.list`, `manual-steps.list`, `defaults-lib.sh`)
- `scripts/` — helpers (`manual-steps.sh`, `pin-dictation-hotkey-164.sh`, `pin-finder-icon-view.sh`)
- `launchagents/` — user LaunchAgent plists (symlinked into `~/Library/LaunchAgents`)
- Scripts: `bootstrap.sh`, `install.sh`, `macos.sh`, `dock.sh`, `handlers.sh`, `prune-apps.sh`, `shell.sh`, `hostname.sh`, `check.sh`, `defaults-diff.sh` (see [Scripts](#scripts))
- `tests/`, `hooks/` — unit tests and pre-push lint/test gate
- `SHORTCUTS.md` — keyboard-shortcut cheat-sheets

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

Then run the guided bootstrap. It walks through every step in order (`install.sh` -> `shell.sh` -> `hostname.sh` -> `macos.sh` -> `dock.sh` -> `handlers.sh` -> `prune-apps.sh`), prompting before each, and is idempotent so it's safe to re-run:

```bash
~/.dotfiles-mac/bootstrap.sh --dry-run   # preview every step, change nothing
~/.dotfiles-mac/bootstrap.sh             # run it (prompts before each; --yes skips prompts)
```

### Dotfiles & packages

> _Run first by `bootstrap.sh`; the command below runs only this step._

`install.sh` symlinks the configs into `~/.config` (and `~/.gitconfig`, `~/.hammerspoon`), installs the Brewfile, trusts the `mise` config, and enables the pre-push hook. Idempotent and safe to re-run — it backs up any real file already in the way of a symlink rather than clobbering it. There's no `--dry-run`; it applies changes directly.

```bash
~/.dotfiles-mac/install.sh
```

### Apps not in the Brewfile

> _Manual — no script installs these; do them by hand._

These apps can't be installed by `brew bundle`, so set them up by hand after bootstrapping:

- **Cursor Nightly** — download and install it manually from the [Cursor Nightly download page](https://cursor.com/nightlydownload), as a separate app. It's deliberately kept out of the Brewfile (which installs only the stable Cursor), so the stable build and Nightly sit side by side.
- **YouTube Music** — a Chrome PWA. In Chrome, open `music.youtube.com`, then click the install icon in the address bar (or **⋮ menu → Cast, save, and share → Install page as app**).
- **Okta Verify** — company MDM (Kandji). Listed in `lib/mdm-apps.list`, not the Brewfile: `mas` cannot upgrade the `root:wheel` App Store copy (`No downloads initiated for ADAM ID 490179405`), which breaks `brewsync`. Updates come from MDM / the App Store UI.
- **1Password** (desktop) — company MDM (Kandji Self Service). Listed in `lib/mdm-apps.list`, not the Brewfile, so Homebrew and Kandji never fight over the app. The CLI (`1password-cli` / `op`) stays in the Brewfile; turn on Settings → Developer → Integrate with 1Password CLI in the app.

These are also in the [manual steps](#manual-steps) checklist (`scripts/manual-steps.sh`). Do them before running `dock.sh`, or it'll skip them — `bootstrap.sh` flags any not-yet-installed Dock app before its Dock step, so you can install them first (or re-run `dock.sh` afterwards).

### Set login shell

> _Run by `bootstrap.sh`; the commands below run only this step._

Make Fish (installed by the Brewfile) your login shell. `shell.sh` adds it to `/etc/shells` and runs `chsh` for you — idempotent, and it prompts for your password (sudo) only if a change is actually needed:

```bash
~/.dotfiles-mac/shell.sh --dry-run   # preview
~/.dotfiles-mac/shell.sh             # apply
```

### Set Hostname

> _Run by `bootstrap.sh`; the commands below run only this step._

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

### URL handlers (Chrome, not Apple apps)

`handlers.sh` sets default apps for URL schemes listed in `lib/url-handlers.list` via `duti` (idempotent). That covers `mailto:` plus Music / News / Books / Podcasts / Games schemes so those Apple apps don't claim the links — Chrome handles them instead:

```bash
~/.dotfiles-mac/handlers.sh --dry-run   # preview
~/.dotfiles-mac/handlers.sh             # apply
```

### Unwanted apps (GarageBand, iMovie, Pages)

`prune-apps.sh` removes App Store apps listed in `lib/unwanted-apps.list` (idempotent; needs sudo). System apps like Music/Photos can't be deleted; GarageBand, iMovie, and Pages can. `check.sh` drifts if they reappear.

Wanted Mac App Store apps (WhatsApp, Okta Extension, 1Password for Safari, Keynote, Numbers) are declared in the `Brewfile` via `mas` so `brew bundle` / `check.sh` keep that set closed. Okta Verify is MDM-managed (`lib/mdm-apps.list`), not Brewfile-managed.

```bash
~/.dotfiles-mac/prune-apps.sh --dry-run   # preview
~/.dotfiles-mac/prune-apps.sh             # remove
```

### Quiet Apple apps (containment)

System apps (Music, Photos, News, …) can't be deleted (SIP). This repo contains them where scripting is reliable:

- **URL handlers** → Chrome (`handlers.sh` / `lib/url-handlers.list`)
- **GarageBand / iMovie / Pages** removed (`prune-apps.sh`)
- **Photos auto-open on device connect** Off (`com.apple.ImageCapture disableHotPlug` in `lib/macos-defaults.list`)
- **Menu bar (Tahoe):** Spotlight, Focus, Now Playing hidden (`@host/com.apple.controlcenter` = `8`) via `macos.sh` / `check.sh`
- **Finder sidebar Recents** Off, **icon view 72/13**, **show all filename extensions** On, **status bar** On, **sidebar icon size** Large, and **CotEditor** theme **Anura (Dark)** + monospaced font via `macos.sh` / `check.sh`
- **Login Items:** `check.sh` drifts if ChatGPT, Gemini, or GeminiAppLauncher are enabled at login (apps may stay installed; turn them **Off** in **System Settings → General → Login Items**)

Universal Links like `https://music.apple.com` may still open Apple apps — use Chrome when it matters.

### Keyboard / Dictation / Fn

**Goal:** hold-Fn/Globe must never start the mic (Dictation / Apple Intelligence).

**Scripted + checked** (`macos.sh` / `check.sh`):
- Fn/Globe → **Do Nothing** (`AppleFnUsageType` = `0`)
- Dictation **Off**
- Symbolic hotkey 164 ("Start Dictation") pinned to **Right Command twice** — a *dummy* unused combo so Press 🎙️ / Fn never owns it. Do **not** use Right Command twice yourself; it would fire dictation if Dictation were on.

**After a macOS Software Update:** Apple often rewrites `com.apple.symbolichotkeys` and resets hotkey 164 to the unbound default (`enabled=0`, `type=standard`, `parameters=(65535,65535,0)`). That is what happened after Tahoe **26.7** / **27.0**. A login LaunchAgent (`com.pdone.pin-dictation-hotkey-164`, installed by `install.sh`) re-runs `scripts/pin-dictation-hotkey-164.sh` at every login so the pin returns after the reboot. The weekday drift check and `macos.sh` remain backups. Other managed `defaults` usually survive; this nested hotkey map does not.

**Karabiner** (Brewfile cask `karabiner-elements`; `karabiner/` → `~/.config/karabiner/` as a **directory** symlink — Karabiner won't watch a file symlink):
- Fn/Globe only sets internal variable `pdone_fn` (never sent to macOS)
- While held: Fn+F → ⌃⌘F (fullscreen); Fn+F11 → Show Desktop; Fn+Delete → forward-delete; Fn+arrows → Home/End/PgUp/PgDn
- Dictation/microphone consumer keys swallowed; Finder Forward Delete → Move to Trash
- Top-row brightness/volume still work without Fn
- `check.sh` drifts if the dir symlink, Fn-kill rule, or Finder Trash rule is missing

**Manual once (TCC / DriverKit):** Driver Extensions + Device Control and Data Access (Karabiner-Core-Service) + Allow in the Background — see [Manual steps](#manual-steps) (`karabiner-*`; `check.sh` verifies the driver and the Core-Service grant). Karabiner 16+ does not need Input Monitoring. If DriverKit never enables, work MDM/EDR may be blocking Team ID `G43BCU2T37`.

### Hammerspoon (Sidecar → Slack)

[Hammerspoon](https://www.hammerspoon.org/) (Brewfile cask `hammerspoon`) runs small Lua automations. `hammerspoon/` → `~/.hammerspoon/` as a **directory** symlink (`lib/links.list`), so `init.lua` and its sibling modules load straight from the repo. `init.lua` just loads the modules listed in `MODULES`; add new automations as their own `*.lua` file there. It also sets: start at login, menu-bar icon only (no Dock icon), no crash-report upload, and loads `hs.ipc` so the `hs` CLI works.

**`sidecar_slack.lua`** replaces the by-hand Sidecar routine:
- **Sidecar starts** (a screen whose name contains "Sidecar" or "iPad" appears): Slack's window moves to the iPad, goes full screen, and gets one `Cmd -` (zoom out).
- **Sidecar stops:** Slack leaves full screen, returns to the built-in display, and gets one `Cmd =` — only if the module zoomed it out earlier, so the zoom always stays balanced.
- Does nothing if Slack isn't running. Screen changes are debounced and only real Sidecar on/off transitions act.
- **Manual toggle / test:** `Shift + Control + Option + Command + S`.
- Screen names are logged to the Hammerspoon Console (menu-bar icon → Console). Status from a terminal: `hs -c 'loaded.sidecar_slack.status()'`. If your iPad shows up under another name: `hs -c "hs.settings.set('sidecar_slack.screenNames', {'Sidecar', 'iPad', '<name>'}); hs.reload()"`.
- `check.sh` drifts if the `~/.hammerspoon` symlink or the cask is missing, warns if Hammerspoon isn't running, and (Manual steps section) warns if it lacks Device Control and Data Access. `macos.sh` / `check.sh` also manage its Dock-icon and crash-upload prefs (`lib/macos-defaults.list`).

**Manual once (TCC):** System Settings → Privacy & Security → **Device Control and Data Access** (called Accessibility before macOS 27) → enable **Hammerspoon**; restart Hammerspoon after granting (it can't move windows or send keys without it), then menu-bar icon → **Reload Config**. Test by turning Sidecar on and off. (Step `hammerspoon-ax` in [Manual steps](#manual-steps).)

### macOS defaults

> _Run by `bootstrap.sh`; the commands below run only this step._

A curated set of macOS `defaults` is applied by `macos.sh` (plus Dictation hotkey 164, CotEditor theme/font, and Finder sidebar Recents):

```bash
~/.dotfiles-mac/macos.sh --dry-run   # preview every decision, write nothing
~/.dotfiles-mac/macos.sh             # apply
```

Safe to re-run: it reads and type-checks each setting first, then writes the desired value (re-asserting even when it already matches), skips any key whose stored type is unexpected (with a warning), and sets missing keys. Before the first actual change it backs up each affected domain to `backups/defaults-<timestamp>/`. UI restarts (Dock, Finder, menu bar) happen at the end only when something actually changed, after you confirm.

Run `macos.sh --list` to see the exact set of settings it manages (printed as a Markdown table).

### Verifying the setup

> _Standalone tool — not run by `bootstrap.sh`; run it whenever you want to check for drift._

`check.sh` is read-only: reports drift vs the repo (symlinks, Brewfile + undeclared extras, defaults, Dock, shell, hostname, handlers, unwanted apps, Dictation/Karabiner/Hammerspoon/Login Items/Recents/CotEditor/`*.app.back`, FileVault / pending updates, …) and ends with the [manual steps](#manual-steps): failed automated checks are warnings (not drift), and steps with no reliable check show as `info` lines, counted as "to check by hand" in the summary. Exits non-zero on drift — run after macOS updates:

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
- Settings not exposed via `defaults` (private-API sliders, sudo-only, TCC-gated) won't show up — those stay in `lib/manual-steps.list` (see [Manual steps](#manual-steps)).

### Manual steps

> _Manual — no script can do these. `install.sh` and `bootstrap.sh` print this checklist when they finish and, on a terminal, offer to walk through it._

Some setup can't be scripted: privacy permissions (TCC / DriverKit), sign-ins, company MDM apps, and settings that aren't exposed via `defaults`, are SIP-protected, device-specific or fragile to write (notifications, Spotlight, display scaling, trackpad/mouse feel). **`lib/manual-steps.list` is the single source of truth** for them; `scripts/manual-steps.sh` reads it:

```bash
~/.dotfiles-mac/scripts/manual-steps.sh list    # numbered checklist
~/.dotfiles-mac/scripts/manual-steps.sh open    # walk through the steps not yet done, opening each System Settings page (terminal only; --all for every step)
~/.dotfiles-mac/scripts/manual-steps.sh check   # read-only: ok / warn / by hand (also the "Manual steps" section of check.sh)
```

`check` never writes a setting or prompts, and wraps every slow call in a timeout. It verifies what it can reliably read: privacy grants from the system TCC database (needs Full Disk Access for the terminal or agent running it, otherwise those become "by hand"), trackpad and pointer `defaults`, the Karabiner driver, the Hammerspoon grant (live via `hs`), installed apps, `gh auth status` and `op whoami`. Steps marked `check.sh` below are verified by their own `check.sh` section. To add a step, add a row to `lib/manual-steps.list` (format in its header) and refresh this table with `scripts/manual-steps.sh list --markdown`.

| # | Step | Where | Checked |
|---|------|------|------|
| 1 | Sign in to the GitHub CLI (needed to clone this private repo) | Terminal: gh auth login | auto |
| 2 | Sign in with your Apple Account (your @icloud.com Apple ID) | System Settings → Apple Account | by hand |
| 3 | iCloud: Photos, iCloud Drive, Messages and other unused sync Off; Passwords (iCloud Keychain) and Find My On | System Settings → Apple Account → iCloud | by hand |
| 4 | Sign in to the App Store (brew bundle needs it for WhatsApp and the other mas apps) | App Store → Store → Sign In | by hand |
| 5 | Install Okta Verify and 1Password from Iru Self Service (Kandji), not Homebrew | Applications → Iru Self Service | check.sh |
| 6 | Sign in to 1Password and unlock it | 1Password app | by hand |
| 7 | Turn on Integrate with 1Password CLI, then run op whoami in a terminal | 1Password → Settings → Developer | auto |
| 8 | Install Cursor Nightly (separate app, next to the stable Cursor) | cursor.com/nightlydownload | auto |
| 9 | Install YouTube Music as a Chrome app | Chrome → music.youtube.com → ⋮ → Cast, save, and share → Install page as app | auto |
| 10 | Allow Hammerspoon (Sidecar → Slack), then restart it and choose Reload Config | System Settings → Privacy & Security → Device Control and Data Access → Hammerspoon | auto |
| 11 | Enable the Karabiner DriverKit VirtualHIDDevice driver | System Settings → General → Login Items & Extensions → Driver Extensions | auto |
| 12 | Allow Karabiner-Elements and Karabiner-Core-Service | System Settings → Privacy & Security → Device Control and Data Access | auto |
| 13 | Allow Karabiner-Elements to run in the background | System Settings → General → Login Items & Extensions → Allow in the Background | by hand |
| 14 | Allow Raycast (needed for Clipboard History) | System Settings → Privacy & Security → Device Control and Data Access → Raycast | auto |
| 15 | Give Ghostty Full Disk Access (lets check.sh read Login Items and Finder Recents) | System Settings → Privacy & Security → Full Disk Access → Ghostty | auto |
| 16 | Give Grok Bot Full Disk Access (for its unattended check.sh runs) | System Settings → Privacy & Security → Full Disk Access → Grok Bot | auto |
| 17 | Trackpad: Tap to click On | System Settings → Trackpad → Point & Click | auto |
| 18 | Trackpad: Click pressure Light | System Settings → Trackpad → Point & Click → Click | auto |
| 19 | Trackpad: Secondary click = Click in bottom right corner | System Settings → Trackpad → Point & Click → Secondary click | auto |
| 20 | Trackpad: Look up & data detectors Off; Force Click and haptic feedback Off | System Settings → Trackpad → Point & Click | by hand |
| 21 | Trackpad: Tracking speed Slower | System Settings → Trackpad → Point & Click → Tracking speed | by hand |
| 22 | Trackpad: Three-finger drag Off | System Settings → Trackpad → More Gestures | auto |
| 23 | Use trackpad for dragging On (Without Drag Lock) | System Settings → Accessibility → Pointer Control → Trackpad Options | auto |
| 24 | Pointer size one notch above Normal | System Settings → Accessibility → Display → Pointer → Pointer size | auto |
| 25 | Mouse: tracking, double-click and scrolling speed faster; secondary click on right side; natural scrolling Off (the global switch also flips the trackpad, so use Logi Options+) | System Settings → Mouse | by hand |
| 26 | Logi Options+: Smooth scrolling On | Logi Options+ → Pointer & Scrolling | by hand |
| 27 | Built-in display: More Space | System Settings → Displays | by hand |
| 28 | Keyboard input source: British | System Settings → Keyboard → Text Input → Input Sources | auto |
| 29 | Remove all desktop widgets | Desktop: right-click each widget → Remove Widget (System Settings → Desktop & Dock → Widgets) | by hand |
| 30 | Set your user picture to the Dog | System Settings → Users & Groups → your account picture | by hand |
| 31 | Notifications Off when mirroring or sharing the display | System Settings → Notifications | by hand |
| 32 | Turn notifications Off for Calendar, Cursor Nightly, FaceTime, Game Center, Home, Mail, Microsoft Teams, Slack, Spotify, Tips, Wallet | System Settings → Notifications → Application Notifications | by hand |
| 33 | Spotlight: turn Off results from Books, Keynote, Mail, Notes, Numbers, Photos, Podcasts, Reminders, Stocks, Tips, Voice Memos | System Settings → Spotlight → Results from Apps | by hand |
| 34 | Keep ChatGPT, Gemini and GeminiAppLauncher Off at login | System Settings → General → Login Items & Extensions | check.sh |
| 35 | Finder View Options: icon size 72, text size 13 (Use as Defaults) | Finder → View → Show View Options (Command+J) | check.sh |
| 36 | Gemini shortcuts: Mini chat Control+Option+G, Full chat Control+Option+Shift+G (defaults clash with ChatGPT) | Gemini → Settings → Shortcuts | by hand |
| 37 | Raycast hotkey: Shift+Control+Command+R (off Option+Space, which clashes with ChatGPT) | Raycast → Settings → General → Raycast Hotkey | by hand |
| 38 | Raycast: Finder hotkey Shift+Control+Command+F | Raycast → type Finder → Command+K → Configure Application… → Record Hotkey | by hand |
| 39 | Raycast Clipboard History: hotkey Control+Command+V, keep history 1 day, disable 1Password and 1Password for Safari | Raycast → Settings → Extensions → Clipboard History | by hand |

Notes: Passwords in iCloud = iCloud Keychain, so don't turn it Off casually. Natural scrolling is left to Logi Options+ because the global switch also flips the trackpad. The Finder, Logi Options+, Gemini and Raycast subsections below have the click-by-click detail.

#### Finder

Per-window View Options and chrome (kept manual so folder views stay intentional; the default icon view 72/13 is pinned by `macos.sh` and checked by `check.sh`):

1. Open any Finder window → **View → Show View Options** (`Command + J`)
2. Set **Icon size** to **72×72**
3. Set **Text size** to **13**
4. Optionally tick **Use as Defaults** if you want new icon-view windows to inherit these sizes
5. **Show Status Bar** — managed by `macos.sh` / `check.sh` (`com.apple.finder ShowStatusBar`); UI path: **View → Show Status Bar**
6. **Show all filename extensions** — managed by `macos.sh` / `check.sh` (`NSGlobalDomain AppleShowAllExtensions`); UI path: **Finder → Settings… → Advanced**

Re-check after a major macOS upgrade; View Options can reset per folder.

#### Logi Options+

| Area | Setting | Value |
|------|------|------|
| Pointer & Scrolling | Smooth scrolling | On |

#### Gemini

Default Gemini shortcuts (`Option + Space` / `Option + Shift + Space`) clash with ChatGPT. Set via Gemini Settings → Shortcuts:

| Action | Shortcut |
|------|------|
| Mini chat | `Control + Option + G` |
| Full chat | `Control + Option + Shift + G` |

#### Raycast

Move Raycast off `Option + Space` (clashes with ChatGPT): Settings → General → Raycast Hotkey → `Shift + Control + Command + R`.

To bind a global hotkey for activating Finder from anywhere:
1. Open Raycast (`Shift + Control + Command + R`)
2. Type **Finder** until "Finder" appears as a command result
3. Highlight it and press `Command + K` (Actions menu)
4. Choose **Configure Application…**
5. Click the **Record Hotkey** field and press `Shift + Control + Command + F`

To enable Clipboard History:
1. Open Raycast and run the **Clipboard History** command once
2. Grant Accessibility permission if prompted (System Settings → Privacy & Security → Device Control and Data Access (Accessibility before macOS 27) → enable Raycast)
3. Bind a hotkey via Raycast Settings → Extensions → search "clipboard", then in the **Clipboard History** row of type **Command** (not the parent "Extension" row), click **Record Hotkey** and press `Control + Command + V`.
   - Avoid `Command + Shift + V` (paste without formatting) and `Command + Option + V` (Finder paste-as-move).
4. Set **Keep History For** to 1 Day
5. Add password apps to **Disabled Applications** so their copies are never recorded: 1Password, 1Password for Safari

## Usage & reference

### Scripts

| Script | What it does, and when to run it |
|------|------|
| `bootstrap.sh` | Guided full setup: runs `install.sh`, `shell.sh`, `hostname.sh`, `macos.sh`, `dock.sh`, `handlers.sh`, `prune-apps.sh` in order, prompting before each. `--dry-run` previews all steps, `--yes` skips prompts. Idempotent. |
| `install.sh` | The dotfiles layer of a fresh-machine setup: preflight, symlinks, Brewfile, `mise` trust, and enabling the pre-push hook; ends with the manual-steps checklist. Does *not* set shell/hostname/defaults/Dock (those are `bootstrap.sh`). Safe to re-run — repoints symlinks, backs up any real file in the way. |
| `check.sh` | Read-only drift check vs the repo (incl. Brewfile extras, FileVault, pending software updates, and the manual-steps checks). Run any time (especially after a macOS update). Exits non-zero on drift. Login Items + Finder Recents need Full Disk Access for the terminal you run it from (Ghostty); Grok Bot already has this for the weekday 9am check. |
| `macos.sh` | Apply managed `defaults` plus Dictation hotkey 164, CotEditor theme/font, and Finder sidebar Recents. `--dry-run` / `--list`. Idempotent. |
| `dock.sh` | Pin the Dock apps in order. Run after the apps are installed and whenever you edit `lib/dock-apps.list`. `--list` previews. Idempotent; needs `dockutil`. |
| `handlers.sh` | Set URL-scheme default apps from `lib/url-handlers.list` (e.g. mailto → Chrome). `--dry-run` / `--list`. Idempotent; needs `duti`. |
| `prune-apps.sh` | Remove apps listed in `lib/unwanted-apps.list` (GarageBand, iMovie, Pages). `--dry-run` / `--list`. Idempotent; needs `sudo` / `mas`. |
| `shell.sh` | Make fish the login shell. Run once on a fresh machine (see "Set login shell"). Idempotent; sudo/`chsh` only if needed. |
| `hostname.sh` | Set HostName/LocalHostName/ComputerName. Run once on a fresh machine (see "Set Hostname"). Idempotent; sudo only if a name differs. |
| `defaults-diff.sh` | Discover which `defaults` key backs a System Settings toggle, to add to `lib/macos-defaults.list`. Run when you want to manage a new setting. Read-only. |
| `scripts/manual-steps.sh` | The by-hand steps from `lib/manual-steps.list`: `list` (numbered checklist, `--markdown` for the README table), `open` (interactive walk-through that opens each settings page), `check` (read-only ok / warn / by hand; also run by `check.sh`). |

All scripts accept `-h`/`--help`.

### Pre-push checks

A version-controlled git hook (`hooks/pre-push`, enabled by `install.sh` / `bootstrap.sh`
via `core.hooksPath`) mirrors the CI gates locally: before each push it runs `shellcheck`
on the shell scripts, `fish -n` on the fish files, and the `tests/` unit tests (`defaults-lib.test.sh`, `manual-steps.test.sh`). A missing
tool is skipped rather than blocking. Bypass in a pinch with `git push --no-verify`.

### Making changes

Edit configs normally — changes go directly into the repo via symlinks. Then push:

```bash
dotpush "your message"
```

- **New packages:** add to `Brewfile`, run `brewsync`. `check.sh` warns on brew/cask/MAS installs that aren’t declared (does not auto-remove them).
- **Managed macOS settings:** edit `lib/macos-defaults.list`, then run `macos.sh` (use `defaults-diff.sh` to find the key first).
- **Dock apps:** edit `lib/dock-apps.list`, then run `dock.sh`.
- **Desktop assignments:** set each app via its Dock icon → Options → Assign To (macOS has no reliable way to script this), then record it in `lib/desktop-bindings.list` so `check.sh` flags it if macOS drops or moves the pin. Desktop numbers are for the main display.
- **URL handlers:** edit `lib/url-handlers.list`, then run `handlers.sh`.
- **Unwanted apps:** edit `lib/unwanted-apps.list`, then run `prune-apps.sh`.
- **Manual steps:** add a row to `lib/manual-steps.list` (with a read-only check if one is reliable), then refresh the README table with `scripts/manual-steps.sh list --markdown`.
- After any change, run `check.sh` to confirm the machine still matches the repo.

### Fish functions

| Function | Description |
|------|------|
| `brewsync` | Installs, upgrades, and cleans up Homebrew packages from the Brewfile |
| `dotpush <message>` | Commits and pushes all dotfile changes to GitHub in one command |
| `edit <file>` | Opens a file in CotEditor |

### Keyboard shortcuts & reference

See [SHORTCUTS.md](SHORTCUTS.md).
