# dotfiles-mac

Personal macOS dotfiles and bootstrap setup.

## Contents

- `Brewfile` — Homebrew packages and casks
- `fish/` — Fish shell config and functions
- `ghostty/` — Ghostty terminal config
- `karabiner/` — Karabiner-Elements config (directory-symlinked into `~/.config/karabiner`)
- `hammerspoon/` — Hammerspoon Lua automations (directory-symlinked into `~/.hammerspoon`; `init.lua` loads modules such as `sidecar_slack.lua` and the menu-bar mode switcher `mode_switcher.lua` + `modes.lua`)
- `gitconfig` — Git user and behaviour settings
- `mise/` — pinned tool versions (Node 22)
- `lib/` — data for the scripts (`macos-defaults.list`, `dock-apps.list`, `desktop-bindings.list`, `desktop-bindings.py`, `url-handlers.list`, `unwanted-apps.list`, `links.list`, `hostname`, `finder-sidebar-recents.py`, `btm-login-items.py`, `login-items-allow.list`, `crash-reports.py`, `mdm-apps.list`, `manual-steps.list`, `autofix.list`, `logi-expected.list`, `logi-settings.py`, `autofix-lib.sh`, `defaults-lib.sh`)
- `scripts/` — helpers (`manual-steps.sh`, `pin-dictation-hotkey-164.sh`, `pin-quicknote-hotkey-190.sh`, `pin-finder-icon-view.sh`, `load-launchagent.sh`)
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

### Modes (menu-bar switcher)

A Hammerspoon menu-bar dropdown switches between three modes. Switching is **manual only**: no hotkey, no automatic triggers. Settings are in [`hammerspoon/modes.lua`](hammerspoon/modes.lua) (a commented Lua table); the engine is `hammerspoon/mode_switcher.lua`, loaded from `init.lua`.

| Mode | Icon | What it does |
|------|------|------|
| **Normal** | 🖥 `desktopcomputer` | Undoes whatever the last mode recorded: reopens apps it quit (in the background, not hidden), unhides apps it hid, turns its Focus off, lets the display sleep again. Notification badges come back with the Focus. |
| **WebConf** (on air) | red ⏺ `record.circle.fill` | Quits WhatsApp, Spotify and YouTube Music (Chrome app `com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod`); hides Slack, Finder windows and Grok Bot; WebConf Focus on; keeps the display awake; brings Granola to the front. Keeps the Dock. |
| **DeepWork** | `brain.head.profile` + time left (e.g. `42m`) | Quits Slack and WhatsApp, hides Granola, DeepWork Focus on, leaves Spotify alone. Counts down 50 min (`timerMinutes`); at the end a notification offers **Take a break** / **Back to Normal** / **Another session** (it never switches by itself). |

The dropdown ticks the current mode. Under the tick, a disabled line says why you're in it: `WebConf · 12m · Focus on`, `DeepWork · 42m left · Focus on` (time left while the timer is running; otherwise how long the mode has been on), or `Normal · restored`. Focus on/off is included when the switcher knows it. The menu still notes anything missing (Shortcuts) or skipped, and has **Dry run** (prints what a mode would do to the Hammerspoon Console, changes nothing) and **Open switch log**. The icon's tooltip names the mode.

**Safety rails**

- `~/Library/Application Support/pdone-modes/state.json` records the mode and what it changed, written **before** anything changes. After a Hammerspoon reload or a reboot the switcher reads it, shows the persisted mode (re-applying display-awake and the timer), and Normal can still undo everything.
- Switching from one non-Normal mode to another runs Normal's restore first.
- Apps are quit politely (`hs.application:kill()`, like Command-Q), never forced. An app with unsaved work, or one that doesn't quit, is left running and you're told.
- Every switch is logged to `~/Library/Logs/pdone-modes.log` (time, mode, how long the previous mode lasted).
- Menu-bar notification badges can't be switched off (macOS has no API for it), so the Focus is what hides them.

**Focus needs Shortcuts.** macOS doesn't let apps set a Focus, so the switcher runs Shortcuts you create once: `Mode WebConf On` / `Mode WebConf Off` / `Mode DeepWork On` / `Mode DeepWork Off` (one **Set Focus** action each). If any are missing, the mode still runs and the menu says what's missing. The switch also shows a short alert, for example `WebConf Focus skipped — Shortcut missing`, so you notice without opening the menu. A Shortcut that is present does not raise that alert. The manual steps `mode-*` walk through it, and `check.sh` (section **Modes (Hammerspoon)**) checks that the Shortcuts and the WebConf / DeepWork Focus modes exist, that `modes.lua` is valid, and warns if a non-Normal mode has been on for more than `HEALTH_MODE_MAX_HOURS` (4). Apps a mode quit or hid on purpose are listed as info, never drift.

From a terminal:

```bash
hs -c "return loaded.mode_switcher.status()"
hs -c "return loaded.mode_switcher.dryRun('WebConf')"   # or DeepWork / Normal; changes nothing
hs -c "loaded.mode_switcher.switch('Normal')"
```

### App settings as code (Ghostty, Raycast)

**Ghostty: fully in the repo.** `ghostty/config` is symlinked to `~/.config/ghostty/config` (`lib/links.list`). `check.sh` (the **Ghostty config** section) checks four things:

- the link
- that the repo file is valid (`ghostty +validate-config`)
- that no other file Ghostty loads overrides it (`~/Library/Application Support/com.mitchellh.ghostty/config` or `config.ghostty`, and `~/.config/ghostty/config.ghostty`)
- that Ghostty's effective config (`ghostty +show-config`) is exactly what the repo file alone produces

A broken link is restored by `check.sh --fix`. An override file is reported but never deleted automatically.

**Raycast: partly readable.** Raycast keeps almost everything in an encrypted database (`~/Library/Application Support/com.raycast.macos/raycast-enc.sqlite`). The only setting readable from `defaults` is the launcher hotkey: `com.raycast.macos raycastGlobalHotkey` = `Shift-Control-Command-15`, where key code 15 is R. The manual-steps check for that step reads it automatically.

The Finder hotkey (Shift+Control+Command+F) and the Clipboard History settings (Control+Command+V, 1-day history, 1Password and 1Password for Safari excluded) live only in the encrypted database, so they stay **by hand**.

Raycast's supported backup is **Export Settings & Data**, a passphrase-encrypted `.rayconfig` file (Raycast → Settings → Advanced → Export, or Scheduled Backup). Restoring it is a GUI step: Import Settings & Data, then tick **Settings, Aliases & Hotkeys**. The export also holds clipboard history, AI chats, notes, MCP servers and extension settings (which can include tokens), so it is **never stored in this repo**. `*.rayconfig` is gitignored. Keep it in a synced folder via Scheduled Backup instead. Writing the hotkey back with `defaults write` isn't a supported restore (Raycast holds it in memory and in its database), so the step stays manual (`raycast-import` / `raycast-hotkey` in [Manual steps](#manual-steps)).

**Logi Options+: checked, never written.** Logi Options+ keeps its settings as JSON inside a private SQLite database (`~/Library/Application Support/LogiOptionsPlus/settings.db`; the agent caches it and syncs it to the mouse). `lib/logi-settings.py` copies the database (plus its `-wal` / `-shm`) to a temp dir, reads the copy read-only, deletes it, and compares the MX Master 3S values (found by model `2b034`, not serial number) with `lib/logi-expected.list`: main wheel Natural + smooth + SmartShift, thumb wheel horizontal scroll + smooth, gesture button window navigation, pointer speed 0.12. The **Logi Options+** section of `check.sh` reports drift as **Needs Paul** (`logi-settings` in `lib/autofix.list`; `--fix` never touches it), and a missing app, missing database or unreadable format as a warning (`logi-unreadable`), never a failure of the run. Restore is by hand in the app or from Logi's cloud backup (manual step `logi-cloud-backup`). Cloud backup itself stays **by hand**: the **Automatically backup all devices** toggle and the last-backup time aren't in any readable local file (the per-device `settings_backup_state_v2` flags in `settings.db` stay false with backup on), so there's nothing reliable to check. Manual step `logi-smooth-scrolling` uses the same helper (`logi:<id>` check).

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

By default `check.sh` is read-only (see [Read-only vs `--fix`](#read-only-vs---fix-self-healing-drift) for the opt-in self-healing mode): it reports drift vs the repo (symlinks, Brewfile + undeclared extras, defaults, Dock, shell, hostname, handlers, unwanted apps, Dictation/Karabiner/Hammerspoon/Login Items/Recents/CotEditor/Ghostty config/Logi Options+/Modes/`*.app.back`, FileVault / pending updates, …) and ends with the [manual steps](#manual-steps): failed automated checks are warnings (not drift), and steps with no reliable check show as `info` lines, counted as "to check by hand" in the summary. Exits non-zero on drift — run after macOS updates:

```bash
~/.dotfiles-mac/check.sh
~/.dotfiles-mac/check.sh --health-json   # same checks, JSON summary only (for the weekly health note)
~/.dotfiles-mac/check.sh --fix           # also repair SAFE drift, re-check, list Fixed / Needs Paul
```

It ends with a short summary (coloured on a terminal: zero counts dimmed, drift red and warnings yellow when above zero; plain text with `--no-color` or when piped):

```
Summary
  ✔ ok           138 / 139
  ✖ drift          0
  ⚠ warnings       1
  ✋ by hand      20   (scripts/manual-steps.sh list)
  1 needs attention (1 warning)
```

The last line is the verdict (`All good` when there's no drift and no warning). If some of the issues are SAFE to repair, a `→ run ./check.sh --fix to repair N safe item(s)` line appears above it. With `--fix` it also shows `↻ fixed` (`↻ would fix` on a dry run) and `☞ needs Paul`, and drift / warnings are the counts left after the fixes (`(was N before --fix)`). The summary is for people: scripts and routines should read `--health-json`, which is unchanged.

#### Read-only vs `--fix` (self-healing drift)

`check.sh` on its own **never changes anything**. `check.sh --fix` runs the same checks, then repairs only the drift that is classed **SAFE**, re-runs the checks to confirm each fix stuck, and ends with two lists: **Fixed** and **Needs Paul**. Anything that didn't stick moves to Needs Paul, with the reason.

```bash
~/.dotfiles-mac/check.sh --fix --dry-run   # show what would be fixed; change nothing
~/.dotfiles-mac/check.sh --fix             # apply the SAFE fixes, re-check, report
~/.dotfiles-mac/check.sh --fix --health-json   # JSON, plus fixed[] / needs_paul[] (would_fix[] on a dry run)
```

The split lives in one place, `lib/autofix.list`. Every drift or warning in `check.sh` carries an issue id from that list (`fixid <id>`), and `tests/autofix.test.sh` keeps the two in sync. A SAFE fix reuses the existing setter rather than duplicating it. Every fix is idempotent and logged to `~/Library/Logs/com.pdone.check-fix.log`. With `--fix` the exit status reflects the drift left **after** the fixes.

**SAFE: applied automatically (reversible preference writes)**

| Issue | How it's fixed |
|------|------|
| A `lib/macos-defaults.list` value (Dock size / recents / Spaces, Finder views, menu bar, …) | `macos.sh --only <domain\|key> --yes`: backs the domain up to `backups/` first, restarts Dock / Finder / SystemUIServer only if a value actually changed, and reports `logout`-class settings as "log out to finish" |
| Finder icon view 72/13, Finder sidebar Recents, CotEditor theme / font | `macos.sh --only @finder-icon-view` / `@finder-recents` / `@coteditor` (the existing `scripts/pin-finder-icon-view.sh` and `lib/finder-sidebar-recents.py`) |
| Dictation hotkey 164 | `macos.sh --only @dictation-164`, which runs `scripts/pin-dictation-hotkey-164.sh` |
| Quick Note hotkey 190 | `macos.sh --only @quicknote-190`, which runs `scripts/pin-quicknote-hotkey-190.sh` |
| Repo LaunchAgent not loaded | `scripts/load-launchagent.sh` (bootstraps it only if it isn't loaded; `install.sh` uses the same script with `--reload`) |
| Repo-managed symlink missing or pointing elsewhere | `ln -sfn` to the repo file, **only** when the target is a symlink or missing. A real file in the way is never overwritten; that becomes Needs Paul |
| Hammerspoon not running | `open -g -a Hammerspoon` |

**Needs Paul: reported, never automated**

- Installing, uninstalling or updating apps (Brewfile / `brewsync`, which the routine runs separately; `prune-apps.sh`), and the Dock app layout (`dock.sh` rebuilds the whole Dock)
- Login items, desktop assignments (macOS can't script them) and URL handlers (macOS may ask to confirm)
- TCC permissions and the [manual steps](#manual-steps)
- MDM, security settings, software updates, and Mac health signals
- Hostname and login shell (they need sudo), and anything else that needs sudo or deletes files
- Dotfiles git state (no automatic commits, pushes or pulls), including repo files such as `karabiner.json` or a missing script
- Any issue whose id isn't in `lib/autofix.list` (unclassified means report only)

To make a new check self-healing, tag it with `fixid <id>` in `check.sh` and add a `SAFE` row with a fixer to `lib/autofix.list`. The test fails if the two disagree.

#### Mac health

`check.sh`'s **Mac health** section adds read-only, timeout-guarded signals. Problems are warnings, never drift; anything that can't be read without sudo or Full Disk Access becomes an `info` (check by hand) line. Thresholds live in one block (`HEALTH_*`) at the top of that section in `check.sh`:

| Signal | Source | Warns when |
|------|------|------|
| Battery | `system_profiler SPPowerDataType` (fallback `ioreg -rn AppleSmartBattery`) | condition isn't Normal, or maximum capacity < 80% (ok line shows capacity and cycle count) |
| Disk | `df -k /System/Volumes/Data` | free space < 50 GB or < 15% |
| Uptime | `sysctl kern.boottime` | > 14 days since the last restart |
| Memory | `sysctl vm.swapusage`, `kern.memorystatus_vm_pressure_level`, `memory_pressure -Q` | swap in use > 8 GB, or memory pressure critical |
| Storage hogs | `du -sk` of `~/Library/Caches`, Docker Desktop's `Docker.raw` (allocated size), `brew --cache`, Xcode DerivedData (if present) | Caches > 20 GB, Docker > 60 GB, brew cache > 5 GB (`brew cleanup --prune=all`), DerivedData > 20 GB; each warning names the fix |
| Security basics | `socketfilterfw --getglobalstate`, `spctl --status`, `csrutil status`, launchd jobs `com.openssh.sshd` / `com.apple.screensharing` / `com.apple.smbd` or a listener on 22 / 5900 / 445 (no sudo), `sysadminctl -screenLock status` | Firewall, Gatekeeper or SIP off; Remote Login, Screen Sharing or File Sharing on; password not required immediately after sleep / screen saver. Firewall and screen lock may be MDM-managed |
| MDM | `profiles status -type enrollment`, launchd `io.kandji.kandji-daemon` + `io.kandji.kandji-agent` (Iru Daemon / Iru Agent) | not enrolled, or the Iru (Kandji) daemon or agent isn't running |
| Crashes | `lib/crash-reports.py` over `/Library/Logs/DiagnosticReports` and `~/Library/Logs/DiagnosticReports` (+ `Retired/`), last 7 days | any kernel panic (`*.panic` / bug_type 210), or ≥ 3 crashes (bug_type 309) of one app, named. Non-fatal `ExcUserFault_*` reports are counted as faults, not crashes |
| Background jobs | `launchctl print gui/<uid>/<label>` for every LaunchAgent in `lib/links.list`; Hammerspoon running (Hammerspoon section) | an agent isn't loaded or its last exit code isn't 0 (the dictation agent's "loaded" state stays a drift check in its own section) |
| Dotfiles in sync | `git status --porcelain` (gitignored `.agent-logs/` doesn't count) and `git rev-list HEAD...origin/main` | uncommitted / untracked changes, or ahead of / behind `origin/main`. **No network:** it compares with `origin/main` as of the last fetch or push (shown in the ok line), so `check.sh` stays offline and read-only; run `git fetch` first if you need it fresh |
| Login / background items | `lib/btm-login-items.py --audit lib/login-items-allow.list` | an enabled item is neither on `lib/login-items-allow.list` nor approved by an MDM Service Management rule (Kandji pushes these; the helper reads them from the BTM store), or a stale item points to an app that no longer exists |

FileVault and pending software updates are covered under **Security hygiene**. To accept a new login item, add a `team|`, `bundle|`, `label|` or `label-prefix|` row to `lib/login-items-allow.list` (format in its header). To see every enabled item and how it's classified: `python3 lib/btm-login-items.py --audit lib/login-items-allow.list`. Reading the BTM store needs Full Disk Access for the terminal (Ghostty) or agent running `check.sh`.

**Machine-readable summary:** `./check.sh --health-json` runs the same checks but prints only JSON on stdout (same exit status): `generated`, `host`, `summary` (`checked`, `ok`, `drift`, `warnings`, `by_hand`), `battery` (`condition`, `max_capacity_pct`, `cycle_count`), `disk` (`free_gb`, `free_pct`, `total_gb`), `uptime` (`days`), `memory` (`pressure`, `free_pct`, `swap_used_gb`), `storage` (`caches_gb`, `docker_gb`, `brew_cache_gb`, `derived_data_gb`), `security` (`firewall`, `gatekeeper`, `sip`, `remote_login`, `screen_sharing`, `file_sharing`, `screen_lock`), `mdm` (`enrolled`, `agent_running`), `crashes` (`days`, `kernel_panics`, `app_crashes`, `user_faults`, `by_app{}`, `panic_files[]`), `background_jobs` (`hammerspoon_running`, `launch_agents[]` with `label` / `loaded` / `last_exit`), `dotfiles` (`uncommitted`, `ahead`, `behind`, `last_fetch`), `login_items` (`enabled`, `allow_listed`, `mdm_approved`, `unknown[]`, `stale[]`), plus `drift_messages[]` and `warning_messages[]`. Each section also has a `status`. The weekly health note is built from this.

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

`check` never writes a setting or prompts, and wraps every slow call in a timeout. It verifies what it can reliably read: privacy grants from the system TCC database (needs Full Disk Access for the terminal or agent running it, otherwise those become "by hand"), trackpad and pointer `defaults`, the Karabiner driver, the Hammerspoon grant (live via `hs`), installed apps, Logi Options+ values (from a temp copy of its settings database), `gh auth status` and `op whoami`. Steps marked `check.sh` below are verified by their own `check.sh` section. To add a step, add a row to `lib/manual-steps.list` (format in its header) and refresh this table with `scripts/manual-steps.sh list --markdown`.

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
| 25 | Mouse (System Settings): tracking, double-click and scrolling speed faster; secondary click on right side (the wheel's direction, Natural, is set in Logi Options+ and checked by check.sh) | System Settings → Mouse | by hand |
| 26 | Logi Options+: Smooth scrolling On (main wheel and thumb wheel) | Logi Options+ → MX Master 3S → Point & Scroll | auto |
| 27 | Logi Options+: sign in and turn on cloud backup (Automatically backup all devices); confirm it shows a recent Last backup | Logi Options+ → MX Master 3S → Settings → Other → Automatically backup all devices | by hand |
| 28 | Built-in display: More Space | System Settings → Displays | by hand |
| 29 | Keyboard input source: British | System Settings → Keyboard → Text Input → Input Sources | auto |
| 30 | Remove all desktop widgets | Desktop: right-click each widget → Remove Widget (System Settings → Desktop & Dock → Widgets) | by hand |
| 31 | Set your user picture to the Dog | System Settings → Users & Groups → your account picture | by hand |
| 32 | Notifications Off when mirroring or sharing the display | System Settings → Notifications | by hand |
| 33 | Turn notifications Off for Calendar, Cursor Nightly, FaceTime, Game Center, Home, Mail, Microsoft Teams, Slack, Spotify, Tips, Wallet | System Settings → Notifications → Application Notifications | by hand |
| 34 | Spotlight: turn Off results from Books, Keynote, Mail, Notes, Numbers, Photos, Podcasts, Reminders, Stocks, Tips, Voice Memos | System Settings → Spotlight → Results from Apps | by hand |
| 35 | Keep ChatGPT, Gemini and GeminiAppLauncher Off at login | System Settings → General → Login Items & Extensions | check.sh |
| 36 | Gemini shortcuts: Mini chat Control+Option+G, Full chat Control+Option+Shift+G (defaults clash with ChatGPT) | Gemini → Settings → Shortcuts | by hand |
| 37 | Raycast: on a new Mac, import your .rayconfig backup (tick Settings, Aliases & Hotkeys), or set the three Raycast items below by hand; keep Scheduled Backup on (never in this repo: it holds clipboard history and extension settings) | Raycast → Import Settings & Data (backups: Raycast → Settings → Advanced → Export / Scheduled Backup) | by hand |
| 38 | Raycast hotkey: Shift+Control+Command+R (off Option+Space, which clashes with ChatGPT) | Raycast → Settings → General → Raycast Hotkey | auto |
| 39 | Raycast: Finder hotkey Shift+Control+Command+F | Raycast → type Finder → Command+K → Configure Application… → Record Hotkey | by hand |
| 40 | Raycast Clipboard History: hotkey Control+Command+V, keep history 1 day, disable 1Password and 1Password for Safari | Raycast → Settings → Extensions → Clipboard History | by hand |
| 41 | Create two Focus modes named WebConf and DeepWork (WebConf: allow Granola; DeepWork: allow Hammerspoon, so the end-of-session notification gets through) | System Settings → Focus → Add Focus… → Custom | check.sh |
| 42 | Create four Shortcuts, each with one Set Focus action: "Mode WebConf On" (Turn WebConf On until Turned Off), "Mode WebConf Off" (Turn WebConf Off), "Mode DeepWork On", "Mode DeepWork Off" | Shortcuts → + → search "Set Focus" | check.sh |
| 43 | Hammerspoon notifications: style Alerts, so the DeepWork end-of-session buttons (Take a break / Back to Normal / Another session) show | System Settings → Notifications → Hammerspoon → Alerts | by hand |
| 44 | Pin the mode-switcher menu-bar icon so it stays visible: hold Command (⌘) and drag it toward Control Centre / the clock, because icons further from them get auto-hidden behind << | Menu bar → ⌘-drag the mode icon (desktop computer / red ⏺ / brain) | by hand |

Notes: Passwords in iCloud = iCloud Keychain, so don't turn it Off casually. Mouse-wheel direction (Natural) is set in Logi Options+, not System Settings: the macOS natural-scrolling switch is global and also flips the trackpad. The Logi Options+ values are checked automatically (see below). The Finder, Logi Options+, Gemini and Raycast subsections below have the click-by-click detail.

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

MX Master 3S settings, all checked read-only by the **Logi Options+** section of `check.sh` (expected values: `lib/logi-expected.list`):

| Area | Setting | Value |
|------|------|------|
| Point & Scroll → Scroll wheel | Scroll direction | Natural |
| Point & Scroll → Scroll wheel | Smooth scrolling | On |
| Point & Scroll → Scroll wheel | SmartShift | On |
| Point & Scroll → Thumb wheel | Smooth scrolling | On |
| Buttons → Thumb wheel | Action | Horizontal scroll |
| Buttons → Gesture button | Action | Window navigation |
| Point & Scroll → Pointer speed | Speed | 0.12 (±0.02) |

Cloud backup: sign in to a Logi account in the app, then **MX Master 3S → Settings → Other** and turn on **Automatically backup all devices**; it shows **Last backup on …** underneath. Not readable locally, so manual step `logi-cloud-backup` is by hand.

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
| `check.sh` | Read-only drift check vs the repo (incl. Brewfile extras, FileVault, pending software updates, Mac health, and the manual-steps checks). `--health-json` prints a JSON summary instead. `--fix` (optionally with `--dry-run`) also applies the SAFE fixes from `lib/autofix.list`, re-checks, and lists Fixed / Needs Paul. Run any time (especially after a macOS update). Exits non-zero on drift. Login Items + Finder Recents need Full Disk Access for the terminal you run it from (Ghostty); Grok Bot already has this for the weekday 9am check. |
| `macos.sh` | Apply managed `defaults` plus Dictation hotkey 164, CotEditor theme/font, and Finder sidebar Recents. `--dry-run` / `--list`. `--only <id>` (repeatable) and `--yes` (restart without prompting) are what `check.sh --fix` uses. Idempotent. |
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
on the shell scripts, `fish -n` on the fish files, and the `tests/` unit tests (`defaults-lib.test.sh`, `manual-steps.test.sh`, `autofix.test.sh`, `logi-settings.test.sh`, `check-summary.test.sh`, `modes.test.sh`). A missing
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
