# Setup

See [README.md](../README.md).

The one-paste block for a fresh Mac is at the top of the README. This is the rest of the walkthrough: what each step runs, how to check the machine afterwards, and where the repo files live. What a managed setting does is in [Settings](settings.md). The by-hand checklist is [Manual steps](manual-steps.md). After a software update, hotkey pins, and AC sleep are in [Troubleshooting](troubleshooting.md). Hammerspoon modes are in [Modes](modes.md).

## What's in the repo

- `Brewfile` — Homebrew packages and casks
- `fish/` — Fish shell config and functions
- `ghostty/` — Ghostty terminal config
- `karabiner/` — Karabiner-Elements config (directory-symlinked into `~/.config/karabiner`)
- `hammerspoon/` — Hammerspoon Lua automations (directory-symlinked into `~/.hammerspoon`; `init.lua` loads modules such as `sidecar_slack.lua` and the menu-bar mode switcher `mode_switcher.lua` + `modes.lua`)
- `gitconfig` — Git user and behaviour settings
- `mise/` — pinned tool versions (Node 22)
- `lib/` — data for the scripts (`macos-defaults.list`, `dock-apps.list`, `desktop-bindings.list`, `desktop-bindings.py`, `url-handlers.list`, `file-handlers.list`, `file-handlers.py`, `auto-brightness.py`, `ac-sleep.py`, `unwanted-apps.list`, `links.list`, `hostname`, `finder-sidebar-recents.py`, `btm-login-items.py`, `login-items-allow.list`, `crash-reports.py`, `mdm-apps.list`, `manual-steps.list`, `autofix.list`, `logi-expected.list`, `logi-settings.py`, `notification-prefs.py`, `notifications-off.list`, `notifications-reviewed.list`, `display-resolution.py`, `display-resolution.list`, `autofix-lib.sh`, `defaults-lib.sh`, `session-checks.sh`)
- `scripts/` — helpers (`manual-steps.sh`, `render-manual-steps-doc.sh`, `pin-dictation-hotkey-164.sh`, `pin-quicknote-hotkey-190.sh`, `pin-finder-icon-view.sh`, `install-launchagent.sh`, `load-launchagent.sh`)
- `launchagents/` — user LaunchAgent plists. Installed as regular files in `~/Library/LaunchAgents` (`@HOME@` in `WatchPaths` is replaced with `$HOME`; launchd does not expand `~` or `$HOME`)
- Scripts: `bootstrap.sh`, `install.sh`, `macos.sh`, `dock.sh`, `handlers.sh`, `prune-apps.sh`, `shell.sh`, `hostname.sh`, `macconfig-check.sh`, `check.sh`, `defaults-diff.sh` (see [Scripts](#scripts))
- `docs/` — this walkthrough, [settings](settings.md), [manual steps](manual-steps.md), [troubleshooting](troubleshooting.md), and [modes](modes.md)
- `tests/`, `hooks/` — unit tests (`tests/run-all.sh` discovers `tests/*.test.sh`) and the pre-push lint/test gate
- `SHORTCUTS.md` — keyboard-shortcut cheat-sheets

## Bootstrap

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

The same block is at the top of [README.md](../README.md#setup).

## Dotfiles & packages

> _Run first by `bootstrap.sh`; the command below runs only this step._

`install.sh` symlinks the configs into `~/.config` (and `~/.gitconfig`, `~/.hammerspoon`), renders the login LaunchAgents into `~/Library/LaunchAgents` (`scripts/install-launchagent.sh` replaces `@HOME@` with `$HOME`, then bootout/bootstraps the job), installs the Brewfile, trusts the `mise` config, and enables the pre-push hook. Idempotent and safe to re-run — it backs up any real file already in the way of a symlink rather than clobbering it. There's no `--dry-run`; it applies changes directly.

```bash
~/.dotfiles-mac/install.sh
```

## Apps not in the Brewfile

> _Manual — no script installs these; do them by hand._

These apps can't be installed by `brew bundle`, so set them up by hand after bootstrapping:

- **Cursor Nightly** — download and install it manually from the [Cursor Nightly download page](https://cursor.com/nightlydownload), as a separate app. It's deliberately kept out of the Brewfile (which installs only the stable Cursor), so the stable build and Nightly sit side by side.
- **YouTube Music** — a Chrome PWA. In Chrome, open `music.youtube.com`, then click the install icon in the address bar (or **⋮ menu → Cast, save, and share → Install page as app**).
- **Okta Verify** — company MDM (Kandji). Listed in `lib/mdm-apps.list`, not the Brewfile: `mas` cannot upgrade the `root:wheel` App Store copy (`No downloads initiated for ADAM ID 490179405`), which breaks `brewsync`. Updates come from MDM / the App Store UI.
- **1Password** (desktop) — company MDM (Kandji Self Service). Listed in `lib/mdm-apps.list`, not the Brewfile, so Homebrew and Kandji never fight over the app. The CLI (`1password-cli` / `op`) stays in the Brewfile; turn on Settings → Developer → Integrate with 1Password CLI in the app.

These are also in the [manual steps](manual-steps.md) checklist (`manualsteps`, or `scripts/manual-steps.sh`). Do them before running `dock.sh`, or it'll skip them — `bootstrap.sh` flags any not-yet-installed Dock app before its Dock step, so you can install them first (or re-run `dock.sh` afterwards).

## Set login shell

> _Run by `bootstrap.sh`; the commands below run only this step._

Make Fish (installed by the Brewfile) your login shell. `shell.sh` adds it to `/etc/shells` and runs `chsh` for you — idempotent, and it prompts for your password (sudo) only if a change is actually needed:

```bash
~/.dotfiles-mac/shell.sh --dry-run   # preview
~/.dotfiles-mac/shell.sh             # apply
```

## Set Hostname

> _Run by `bootstrap.sh`; the commands below run only this step._

`hostname.sh` sets HostName, LocalHostName and ComputerName (idempotent; uses sudo only when a name actually differs, and flushes the DNS cache only if something changed):

```bash
~/.dotfiles-mac/hostname.sh --dry-run   # preview
~/.dotfiles-mac/hostname.sh             # apply
```

## Dock

> _Run by `bootstrap.sh` (after the manual apps above); the commands below run only this step._

Pin the apps to the Dock in order (idempotent; uses `dockutil` from the Brewfile):

```bash
~/.dotfiles-mac/dock.sh --list   # preview the apps and their order
~/.dotfiles-mac/dock.sh          # apply
```

## URL handlers (Chrome, not Apple apps)

`handlers.sh` sets default apps for URL schemes listed in `lib/url-handlers.list` via `duti` (idempotent). That covers `http:` / `https:` (the default browser) plus `mailto:` and Music / News / Books / Podcasts / Games schemes so those Apple apps don't claim the links — Chrome handles them instead. Scheme changes are `duti -s <bundle> <scheme>` with no role:

```bash
~/.dotfiles-mac/handlers.sh --dry-run   # preview
~/.dotfiles-mac/handlers.sh             # apply
```

## Finder file handlers (CotEditor, Cursor)

`handlers.sh` also sets the double-click app for each extension in `lib/file-handlers.list` (role `all`): text and config in CotEditor, `.js` and `.swift` in the stable Cursor cask. `macconfig-check.sh` compares each one with `duti -x`. Drift is SAFE, so a later change is:

```bash
git pull && ./macconfig-check.sh --fix
```

`.html` is not in that list. It is `public.html`, and setting it switches the default web browser. The fixer refuses `html` / `htm` / `xhtml`, `public.html` / `public.xhtml`, and any URL scheme. `.cfg`, `.env`, and `.list` have no declared UTI (`duti` error -50 on the dynamic UTI); they are marked `unpinnable` and `macconfig-check.sh` prints info, not DRIFT. `.plist` is also set on `com.apple.property-list` and `com.apple.xml-property-list`, because `duti -x plist` follows `com.apple.property-list`.

## Unwanted apps (GarageBand, iMovie, Pages)

`prune-apps.sh` removes App Store apps listed in `lib/unwanted-apps.list` (idempotent; needs sudo). System apps like Music/Photos can't be deleted; GarageBand, iMovie, and Pages can. `macconfig-check.sh` drifts if they reappear.

Wanted Mac App Store apps (WhatsApp, Okta Extension, 1Password for Safari, Keynote, Numbers) are declared in the `Brewfile` via `mas` so `brew bundle` / `macconfig-check.sh` keep that set closed. Okta Verify is MDM-managed (`lib/mdm-apps.list`), not Brewfile-managed.

```bash
~/.dotfiles-mac/prune-apps.sh --dry-run   # preview
~/.dotfiles-mac/prune-apps.sh             # remove
```

## Quiet Apple apps (containment)

System apps (Music, Photos, News, …) can't be deleted (SIP). This repo contains them where scripting is reliable. The list is in [Settings](settings.md#quiet-apple-apps-containment).

## Keyboard / Dictation / Fn

**Goal:** hold-Fn/Globe must never start the mic (Dictation / Apple Intelligence). The scripted settings and the Karabiner rules are in [Settings](settings.md#keyboard-dictation-fn). What a macOS Software Update does to these hotkeys, and how to reload a LaunchAgent on this Mac, is in [Troubleshooting](troubleshooting.md#after-a-macos-software-update).

## Hammerspoon (Sidecar → Slack)

[Hammerspoon](https://www.hammerspoon.org/) (Brewfile cask `hammerspoon`) runs small Lua automations. `hammerspoon/` → `~/.hammerspoon/` as a **directory** symlink (`lib/links.list`), so `init.lua` and its sibling modules load straight from the repo. `init.lua` just loads the modules listed in `MODULES`; add new automations as their own `*.lua` file there. It also sets: start at login, menu-bar icon only (no Dock icon), no crash-report upload, and loads `hs.ipc` so the `hs` CLI works.

**`sidecar_slack.lua`** replaces the by-hand Sidecar routine:
- **Sidecar starts** (a screen whose name contains "Sidecar" or "iPad" appears): Slack's window moves to the iPad, goes full screen, and gets one `Cmd -` (zoom out).
- **Sidecar stops:** Slack leaves full screen, returns to the built-in display, and gets one `Cmd =` — only if the module zoomed it out earlier, so the zoom always stays balanced.
- Does nothing if Slack isn't running. Screen changes are debounced and only real Sidecar on/off transitions act.
- **Manual toggle / test:** `Shift + Control + Option + Command + S`.
- Screen names are logged to the Hammerspoon Console (menu-bar icon → Console). Status from a terminal: `hs -c 'loaded.sidecar_slack.status()'`. If your iPad shows up under another name: `hs -c "hs.settings.set('sidecar_slack.screenNames', {'Sidecar', 'iPad', '<name>'}); hs.reload()"`.
- `macconfig-check.sh` drifts if the `~/.hammerspoon` symlink or the cask is missing, warns if Hammerspoon isn't running, and (Manual steps section) warns if it lacks Device Control and Data Access. `macos.sh` / `macconfig-check.sh` also manage its Dock-icon and crash-upload prefs (`lib/macos-defaults.list`).

**Manual once (TCC):** System Settings → Privacy & Security → **Device Control and Data Access** (called Accessibility before macOS 27) → enable **Hammerspoon**; restart Hammerspoon after granting (it can't move windows or send keys without it), then menu-bar icon → **Reload Config**. Test by turning Sidecar on and off. (Step `hammerspoon-ax` in [Manual steps](manual-steps.md).)

## Modes (menu-bar switcher)

A Hammerspoon menu-bar dropdown switches between three modes. Switching is **manual only**: no hotkey, no automatic triggers. The modes, the safety rails, and the Focus Shortcuts are in [Modes](modes.md).

## App settings as code (Ghostty, Raycast)

Ghostty is fully in the repo. Raycast is partly readable. Logi Options+ is checked and never written. What each one does is in [Settings](settings.md#app-settings-as-code-ghostty-raycast).

## macOS defaults

> _Run by `bootstrap.sh`; the commands below run only this step._

A curated set of macOS `defaults` is applied by `macos.sh` (plus Dictation hotkey 164, CotEditor theme/font, Finder sidebar Recents, and AC idle sleep):

```bash
~/.dotfiles-mac/macos.sh --dry-run   # preview every decision, write nothing
~/.dotfiles-mac/macos.sh             # apply
```

Safe to re-run: it reads and type-checks each setting first, then writes the desired value (re-asserting even when it already matches), skips any key whose stored type is unexpected (with a warning), and sets missing keys. Before the first actual change it backs up each affected domain to `backups/defaults-<timestamp>/`. UI restarts (Dock, Finder, menu bar) happen at the end only when something actually changed, after you confirm.

What each row does is in [Settings](settings.md#macos-defaults). Run `macos.sh --list` to see the exact set of settings it manages (printed as a Markdown table).

## Verifying the setup

> _Standalone tool — not run by `bootstrap.sh`; run it whenever you want to check for drift._

By default `macconfig-check.sh` is read-only (see [Read-only vs `--fix`](#read-only-vs---fix-self-healing-drift) for the opt-in self-healing mode): it reports drift vs the repo (symlinks, Brewfile + undeclared extras, defaults, Dock, shell, hostname, handlers, unwanted apps, Dictation/Karabiner/Hammerspoon/Login Items/Recents/CotEditor/Ghostty config/Logi Options+/Modes/Notifications/`*.app.back`, FileVault / pending updates, …) and ends with the [manual steps](manual-steps.md): failed automated checks are warnings (not drift), and steps with no reliable check show as `info` lines, counted as "to check by hand" in the summary. Exits non-zero on drift — run after macOS updates:

```bash
macconfig
macconfig --health-json   # same checks, JSON summary only (for the weekly health note)
macconfig --fix           # also repair SAFE drift, re-check, list Fixed / Needs Paul
~/.dotfiles-mac/macconfig-check.sh   # the same script, without fish
```

`macconfig` is a fish function, installed with the others in `fish/functions/`. It runs `macconfig-check.sh` from any directory and passes every argument through (`macconfig --fix`, `macconfig --no-color`, and so on). `check.sh` at the repo root execs `macconfig-check.sh` with the same arguments, stdin, and exit status, so `~/.dotfiles-mac/check.sh --fix --no-color` still works.

It ends with a short summary (coloured on a terminal: zero counts dimmed, drift red and warnings yellow when above zero; plain text with `--no-color` or when piped):

```
Summary
  ✔ ok           138 / 139
  ✖ drift          0
  ⚠ warnings       1
  ✋ by hand      20   (scripts/manual-steps.sh list)
  1 needs attention (1 warning)
    - warn   Mac health: disk: only 12 GB free (8%) on Data (Needs Paul)
```

The verdict is `All good` when there's no drift and no warning, and in that case nothing follows it. Otherwise the verdict is followed by one indented bullet per outstanding drift or warning: the section, a short reason (what was measured against what was expected), and a hint — `fix: <id>` when `./macconfig-check.sh --fix` can repair it, `manual step` for a manual-step warning, otherwise `Needs Paul`. Long reasons are cut so the line stays within 100 columns. Drift bullets are red and warning bullets yellow on a terminal; `--no-color`, `NO_COLOR`, or a pipe leaves them plain. By-hand `info` lines stay in the by hand count. With `--fix` the bullets are what's still outstanding after the fixes. If some of the issues are SAFE to repair, a `→ run ./macconfig-check.sh --fix to repair N safe item(s)` line appears above the verdict. With `--fix` the summary also shows `↻ fixed` (`↻ would fix` on a dry run) and `☞ needs Paul`, and drift / warnings are the counts left after the fixes (`(was N before --fix)`). The summary is for people. Scripts and routines should read `--health-json`: `drift_messages[]` and `warning_messages[]` are still the original messages, and `attention[]` is the same bullet text.

### Read-only vs `--fix` (self-healing drift)

`macconfig-check.sh` on its own **never changes anything**. `macconfig-check.sh --fix` runs the same checks, then repairs only the drift that is classed **SAFE**, re-runs the checks to confirm each fix stuck, and ends with two lists: **Fixed** and **Needs Paul**. Anything that didn't stick moves to Needs Paul, with the reason.

```bash
~/.dotfiles-mac/macconfig-check.sh --fix --dry-run   # show what would be fixed; change nothing
~/.dotfiles-mac/macconfig-check.sh --fix             # apply the SAFE fixes, re-check, report
~/.dotfiles-mac/macconfig-check.sh --fix --health-json   # JSON, plus fixed[] / needs_paul[] (would_fix[] on a dry run)
```

The split lives in one place, `lib/autofix.list`. Every drift or warning in `macconfig-check.sh` carries an issue id from that list (`fixid <id>`), and `tests/autofix.test.sh` keeps the two in sync. A SAFE fix reuses the existing setter rather than duplicating it. Every fix is idempotent and logged to `~/Library/Logs/com.pdone.check-fix.log`. With `--fix` the exit status reflects the drift left **after** the fixes.

**SAFE: applied automatically (reversible preference writes)**

| Issue | How it's fixed |
|------|------|
| A `lib/macos-defaults.list` value (Dock size / recents / minimize into app / no bouncing / Spaces, Finder views, Trash, screenshots, menu bar, Trackpad, window tiling, Stage Manager, desktop widgets, …) | `macos.sh --only <domain\|key> --yes`: backs the domain up to `backups/` first, `mkdir -p`s `~/Pictures/Screenshots` before writing `com.apple.screencapture location`, restarts Dock / Finder / SystemUIServer / ControlCenter only if a value actually changed, and reports `logout`-class settings (including Trackpad) as "log out to finish". Minimize-into-app and no-bouncing use the same Dock restart as the other Dock rows. Menu bar rows restart ControlCenter. Window tiling, Stage Manager, and desktop-widget rows leave `restart` empty, so a repair restarts no process |
| Finder icon view 72/13, Finder sidebar Recents, CotEditor theme / font | `macos.sh --only @finder-icon-view` / `@finder-recents` / `@coteditor` (the existing `scripts/pin-finder-icon-view.sh` and `lib/finder-sidebar-recents.py`) |
| Dictation hotkey 164 | `macos.sh --only @dictation-164`, which runs `scripts/pin-dictation-hotkey-164.sh` |
| Quick Note hotkey 190 | `macos.sh --only @quicknote-190`, which runs `scripts/pin-quicknote-hotkey-190.sh` |
| Repo LaunchAgent not loaded, or the installed plist differs from the rendered repo copy | `scripts/install-launchagent.sh` writes `launchagents/*.plist` with `@HOME@` replaced by `$HOME`. `scripts/load-launchagent.sh` then bootstraps the job if it isn't loaded. If the installed bytes differed (including an old symlink), it `launchctl bootout`s and `bootstrap`s so launchd picks up `WatchPaths`. `install.sh` always reloads |
| Repo-managed symlink missing or pointing elsewhere | `ln -sfn` to the repo file, **only** when the target is a symlink or missing. A real file in the way is never overwritten; that becomes Needs Paul |
| Hammerspoon not running | `open -g -a Hammerspoon` |
| Dock "Assign To" pins (`lib/desktop-bindings.list`) | `lib/desktop-bindings.py --apply`: writes `com.apple.spaces` `app-bindings` (bundle id → that Desktop's current Space UUID on the main display; Desktop 1 is `""`; `none` deletes the key), backs the domain up first, and restarts Dock only if a pin changed. A pin whose Desktop doesn't exist is left for you — Spaces are never created |
| Finder double-click apps (`lib/file-handlers.list`) | `lib/file-handlers.py --apply`: `duti -s <bundle> .<ext> all` for each drifted extension, then polls `duti -x` for a few seconds. Refuses browser types (`html`, `public.html`) and URL schemes. Skips `unpinnable` rows (`.cfg`, `.env`, `.list`) |

**Needs Paul: reported, never automated**

- Installing, uninstalling or updating apps (Brewfile / `brewsync`, which the routine runs separately; `prune-apps.sh`), and the Dock app layout (`dock.sh` rebuilds the whole Dock)
- Login items and URL handlers (macOS may ask to confirm)
- TCC permissions and the [manual steps](manual-steps.md)
- MDM, security settings, software updates, and Mac health signals
- Hostname and login shell (they need sudo), display auto-brightness (System Settings → Displays; the CoreBrightness plist is root-owned and its keys move between macOS versions, so `--fix` does not write it), AC idle sleep (`sudo pmset -c sleep 0`; `macos.sh` runs it and skips when sudo isn't available or isn't wanted, and `--fix` does not run sudo), mouse tracking speed `1.5` and scrolling speed `0.5` (check-only; `defaults write` is unreliable, so `--fix` never writes them), built-in display More Space (read from `system_profiler`; `--fix` never changes the display mode), per-app Allow Notifications (read from the usernoted group plist; `--fix` never writes it), and anything else that needs sudo or deletes files
- Dotfiles git state (no automatic commits, pushes or pulls), including repo files such as `karabiner.json` or a missing script
- Any issue whose id isn't in `lib/autofix.list` (unclassified means report only)

To make a new check self-healing, tag it with `fixid <id>` in `macconfig-check.sh` and add a `SAFE` row with a fixer to `lib/autofix.list`. The test fails if the two disagree.

### Mac health

`macconfig-check.sh`'s **Mac health** section adds read-only, timeout-guarded signals. Problems are warnings, never drift; anything that can't be read without sudo or Full Disk Access becomes an `info` (check by hand) line. Thresholds live in one block (`HEALTH_*`) at the top of that section in `macconfig-check.sh`:

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
| Background jobs | `launchctl print gui/<uid>/<label>` for every plist in `launchagents/`; Hammerspoon running (Hammerspoon section) | an agent isn't loaded or its last exit code isn't 0 (each pin agent's "loaded" and "plist matches" state stays a drift check in its own section) |
| Dotfiles in sync | `git status --porcelain` (gitignored `.agent-logs/` doesn't count) and `git rev-list HEAD...origin/main` | uncommitted / untracked changes, or ahead of / behind `origin/main`. **No network:** it compares with `origin/main` as of the last fetch or push (shown in the ok line), so `macconfig-check.sh` stays offline and read-only; run `git fetch` first if you need it fresh |
| Login / background items | `lib/btm-login-items.py --audit lib/login-items-allow.list` | an enabled item is neither on `lib/login-items-allow.list` nor approved by an MDM Service Management rule (Kandji pushes these; the helper reads them from the BTM store), or a stale item points to an app that no longer exists |

FileVault and pending software updates are covered under **Security hygiene**. To accept a new login item, add a `team|`, `bundle|`, `label|` or `label-prefix|` row to `lib/login-items-allow.list` (format in its header). To see every enabled item and how it's classified: `python3 lib/btm-login-items.py --audit lib/login-items-allow.list`. Reading the BTM store needs Full Disk Access for the terminal (Ghostty) or agent running `macconfig-check.sh`.

**Machine-readable summary:** `./macconfig-check.sh --health-json` runs the same checks but prints only JSON on stdout (same exit status): `generated`, `host`, `summary` (`checked`, `ok`, `drift`, `warnings`, `by_hand`), `battery` (`condition`, `max_capacity_pct`, `cycle_count`), `disk` (`free_gb`, `free_pct`, `total_gb`), `uptime` (`days`), `memory` (`pressure`, `free_pct`, `swap_used_gb`), `storage` (`caches_gb`, `docker_gb`, `brew_cache_gb`, `derived_data_gb`), `security` (`firewall`, `gatekeeper`, `sip`, `remote_login`, `screen_sharing`, `file_sharing`, `screen_lock`), `mdm` (`enrolled`, `agent_running`), `crashes` (`days`, `kernel_panics`, `app_crashes`, `user_faults`, `by_app{}`, `panic_files[]`), `background_jobs` (`hammerspoon_running`, `launch_agents[]` with `label` / `loaded` / `last_exit`), `dotfiles` (`uncommitted`, `ahead`, `behind`, `last_fetch`), `login_items` (`enabled`, `allow_listed`, `mdm_approved`, `unknown[]`, `stale[]`), plus `drift_messages[]`, `warning_messages[]`, and `attention[]` (the same short bullet texts the summary prints under the verdict, without colour; empty when nothing needs attention). Each section also has a `status`. The weekly health note is built from this.

## Discovering new defaults

> _Standalone dev workflow — not part of setup._

To find which `defaults` key backs a System Settings toggle (so you can add it to `lib/macos-defaults.list`), use `defaults-diff.sh`. It compares a before/after pair, so you must actually change the setting in System Settings between the two snapshots — otherwise the snapshots are identical and `diff` reports nothing:

```bash
~/.dotfiles-mac/defaults-diff.sh snapshot before   # capture current state
# ...change ONE setting in System Settings...
~/.dotfiles-mac/defaults-diff.sh snapshot after    # capture again
~/.dotfiles-mac/defaults-diff.sh diff              # changed keys, as list rows
```

`diff` prints each changed/new key as a `domain|key|type|value|…` row in the exact format `lib/macos-defaults.list` expects — paste the matching one in, fill the `restart|area|label|display` columns, then run `macos.sh --dry-run` and `macconfig-check.sh` to confirm. Notes:

- It scans every domain, so the diff usually includes a little unrelated churn (timestamps, recent-item lists), and each snapshot takes a minute or so. Look for the row matching what you toggled and ignore the rest.
- `cfprefsd` caches preferences, so a value you just changed may not appear until you quit and reopen System Settings (or run `killall cfprefsd`) before the `after` snapshot.
- Settings not exposed via `defaults` (private-API sliders, sudo-only, TCC-gated) won't show up — those stay in `lib/manual-steps.list` (see [Manual steps](manual-steps.md)).

## Manual steps

> _Manual — no script can do these. `install.sh` and `bootstrap.sh` print this checklist when they finish and, on a terminal, offer to walk through it._

```bash
manualsteps                                      # check (no arguments): ok / warn / by hand
manualsteps open                                 # walk through the steps not yet done, opening each System Settings page (terminal only; --all for every step)
manualsteps list                                 # numbered checklist
~/.dotfiles-mac/scripts/manual-steps.sh list     # numbered checklist (same as manualsteps list)
~/.dotfiles-mac/scripts/manual-steps.sh open     # walk through the steps not yet done, opening each System Settings page (terminal only; --all for every step)
~/.dotfiles-mac/scripts/manual-steps.sh check    # read-only: ok / warn / by hand (same as manualsteps)
```

`manualsteps` is a fish function, installed with the others in `fish/functions/`. With no arguments it runs `scripts/manual-steps.sh check` from any directory. Arguments pass through (`manualsteps list`, `manualsteps open`, `manualsteps open --all`, `manualsteps check`, `manualsteps --help`) and the script's exit status comes back unchanged.

The checklist, the checks, and the notes under the table are in [Manual steps](manual-steps.md). That file is generated from `lib/manual-steps.list` by `scripts/render-manual-steps-doc.sh`.

## Usage & reference

### Scripts

| Script | What it does, and when to run it |
|------|------|
| `bootstrap.sh` | Guided full setup: runs `install.sh`, `shell.sh`, `hostname.sh`, `macos.sh`, `dock.sh`, `handlers.sh`, `prune-apps.sh` in order, prompting before each. `--dry-run` previews all steps, `--yes` skips prompts. Idempotent. |
| `install.sh` | The dotfiles layer of a fresh-machine setup: preflight, symlinks, rendered login LaunchAgents, Brewfile, `mise` trust, and enabling the pre-push hook; ends with the manual-steps checklist. Does *not* set shell/hostname/defaults/Dock (those are `bootstrap.sh`). If `brew bundle check` fails and stdin is a terminal, it opens the App Store, asks you to sign in, and retries `brew bundle install` once; a non-interactive run keeps the warning. Also `mkdir -p ~/Pictures/Screenshots` (the screenshot save location; existing files are not moved). Renders `launchagents/*.plist` into `~/Library/LaunchAgents` (`@HOME@` → `$HOME`) and bootout/bootstraps each job. Safe to re-run — repoints symlinks, backs up any real file in the way of a symlink. |
| `macconfig-check.sh` | Read-only drift check vs the repo (incl. Brewfile extras, FileVault, pending software updates, Mac health, and the manual-steps checks). `--health-json` prints a JSON summary instead. `--fix` (optionally with `--dry-run`) also applies the SAFE fixes from `lib/autofix.list`, re-checks, and lists Fixed / Needs Paul. Run any time (especially after a macOS update), or use the `macconfig` fish function. Exits non-zero on drift. Login Items + Finder Recents need Full Disk Access for the terminal you run it from (Ghostty); Grok Bot already has this for the weekday 9am check. |
| `check.sh` | Shim that execs `macconfig-check.sh` with the same arguments, stdin, and exit status. Kept so existing callers (the scheduled `~/.dotfiles-mac/check.sh --fix --no-color`, plus muscle memory) stay valid. |
| `macos.sh` | Apply managed `defaults` plus Dictation hotkey 164, CotEditor theme/font, Finder sidebar Recents, and AC idle sleep (`sudo pmset -c sleep 0`, skipped when sudo isn't available or isn't wanted). `--dry-run` / `--list`. `--only <id>` (repeatable) and `--yes` (restart without prompting) are what `macconfig-check.sh --fix` uses. Creates `~/Pictures/Screenshots` with `mkdir -p` before writing `com.apple.screencapture location`. Idempotent. |
| `dock.sh` | Pin the Dock apps in order. Run after the apps are installed and whenever you edit `lib/dock-apps.list`. `--list` previews. Idempotent; needs `dockutil`. |
| `handlers.sh` | Set URL-scheme defaults (`lib/url-handlers.list`) and Finder file defaults (`lib/file-handlers.list`, role `all`). `--dry-run` / `--list`. Idempotent; needs `duti`. |
| `prune-apps.sh` | Remove apps listed in `lib/unwanted-apps.list` (GarageBand, iMovie, Pages). `--dry-run` / `--list`. Idempotent; needs `sudo` / `mas`. |
| `shell.sh` | Make fish the login shell. Run once on a fresh machine (see "Set login shell"). Idempotent; sudo/`chsh` only if needed. |
| `hostname.sh` | Set HostName/LocalHostName/ComputerName. Run once on a fresh machine (see "Set Hostname"). Idempotent; sudo only if a name differs. |
| `defaults-diff.sh` | Discover which `defaults` key backs a System Settings toggle, to add to `lib/macos-defaults.list`. Run when you want to manage a new setting. Read-only. |
| `scripts/manual-steps.sh` | The by-hand steps from `lib/manual-steps.list`: `list` (numbered checklist, `--markdown` for the table in [Manual steps](manual-steps.md)), `open` (interactive walk-through that opens each settings page), `check` (read-only ok / warn / by hand; also run by `macconfig-check.sh`). From fish, `manualsteps` does the same: no arguments runs `check`, and other arguments pass through. |
| `scripts/render-manual-steps-doc.sh` | Regenerates [docs/manual-steps.md](manual-steps.md) from `lib/manual-steps.list`. `--check` exits non-zero when that file is stale. |

All scripts accept `-h`/`--help`.

### Pre-push checks

A version-controlled git hook (`hooks/pre-push`, enabled by `install.sh` / `bootstrap.sh`
via `core.hooksPath`) mirrors the CI gates locally. It runs `fish -n` on the fish files,
then [`tests/run-all.sh`](../tests/run-all.sh). That runner discovers every `tests/*.test.sh`
(including the [Manual steps](manual-steps.md) staleness check inside `manual-steps.test.sh`,
and any other `./tests/*.sh` the hook names), runs them in parallel, and shellchecks the
`.sh` files changed versus the remote commit. When that commit can't be resolved it
shellchecks every `.sh` file. CI calls the same runner: the shell unit-test job runs the
suite, and the shellcheck job runs `tests/run-all.sh --shellcheck all --no-tests`. Another
job copies the repo under `/Users/<name>/.dotfiles-mac-style`, sets `HOME` to match, and
runs the suite there. A missing tool is skipped rather than blocking. Bypass in a pinch
with `git push --no-verify`.

### Making changes

Edit configs normally — changes go directly into the repo via symlinks. Then push:

```bash
dotpush "your message"
```

- **New packages:** add to `Brewfile`, run `brewsync`. `macconfig-check.sh` warns on brew/cask/MAS installs that aren’t declared (does not auto-remove them).
- **Managed macOS settings:** edit `lib/macos-defaults.list`, then run `macos.sh` (use `defaults-diff.sh` to find the key first).
- **Dock apps:** edit `lib/dock-apps.list`, then run `dock.sh`.
- **Desktop assignments:** edit `lib/desktop-bindings.list` (`1`..`N` = Desktop N on the main display, `none` = not assigned), then run `macconfig-check.sh --fix`. That writes `com.apple.spaces` `app-bindings`, resolving Desktop N to the current Space UUID (Desktop 1 is `""`; Desktops 2+ change if Spaces are recreated) and restarts the Dock only if a pin changed. If that Desktop doesn't exist yet, the pin is left for you — the fix never creates Spaces.
- **URL handlers:** edit `lib/url-handlers.list`, then run `handlers.sh`.
- **Finder file handlers:** edit `lib/file-handlers.list` (extension, app, bundle id; optional `unpinnable` or `uti:…`; role is always `all`), then run `macconfig-check.sh --fix` (or `handlers.sh` on a fresh setup). That runs `duti -s <bundle-id> .<ext> all` for whatever drifted. Do not add `html` — it switches the default browser. `.cfg`, `.env`, and `.list` stay `unpinnable`.
- **Display auto-brightness:** Off. `macconfig-check.sh` reads it with `corebrightnessdiag status-info` (no sudo). Turn it off in System Settings → Displays. `--fix` does not write it. True Tone and Slightly dim the display on battery are left alone.
- **AC idle sleep:** Off while on mains power (`sudo pmset -c sleep 0`). Closing the lid still sleeps the Mac, and battery is unchanged. The display still turns off and the screen still locks. `macos.sh` runs the command and skips it when sudo isn't available or isn't wanted. `macconfig-check.sh` reads the `AC Power:` section of `pmset -g custom` and warns if `sleep` isn't 0. `--fix` does not change it. See [Troubleshooting](troubleshooting.md#ac-idle-sleep).
- **Built-in display More Space:** the expected `_spdisplays_resolution` prefix is `lib/display-resolution.list` (`1800 x 1169` on this Color LCD). `macconfig-check.sh` reads `system_profiler SPDisplaysDataType -json` and warns on a mismatch. No built-in panel (clamshell) is an info line. `--fix` does not change the display mode.
- **Notifications:** apps that must have Allow Notifications off are `lib/notifications-off.list`. `macconfig-check.sh` reads the usernoted plist and never writes it. A third-party app you've already looked at goes in `lib/notifications-reviewed.list`. If the bit moves, change `ALLOW_NOTIFICATIONS_BIT` in `lib/notification-prefs.py` (see [Notifications](settings.md#notifications)). Hammerspoon's Alerts style is the same read (`ALERT_STYLE_BIT`).
- **Unwanted apps:** edit `lib/unwanted-apps.list`, then run `prune-apps.sh`.
- **Login LaunchAgents:** edit `launchagents/*.plist`. `WatchPaths` uses `@HOME@`, not `~` or `$HOME` (launchd expands neither). `install.sh` or `macconfig-check.sh --fix` renders the plist into `~/Library/LaunchAgents` and, when the installed file differs, reloads it with `launchctl bootout` then `bootstrap`. These are regular files, not symlinks.
- **Manual steps:** add a row to `lib/manual-steps.list` (with a read-only check if one is reliable), then regenerate [docs/manual-steps.md](manual-steps.md) with `scripts/render-manual-steps-doc.sh` (it runs `scripts/manual-steps.sh list --markdown`).
- After any change, run `macconfig` (or `./macconfig-check.sh`) to confirm the machine still matches the repo.

### Fish functions

| Function | Description |
|------|------|
| `macconfig` | Checks this Mac's config settings against the repo (`macconfig-check.sh`). Arguments pass through: `macconfig`, `macconfig --fix`, `macconfig --no-color` |
| `manualsteps` | By-hand settings (`scripts/manual-steps.sh`). No arguments runs `check`. Arguments pass through: `manualsteps list`, `manualsteps open`, `manualsteps open --all`, `manualsteps --help` |
| `brewsync` | Installs, upgrades, and cleans up Homebrew packages from the Brewfile. Sets `HOMEBREW_NO_ASK` for that run only, so Homebrew 7 does not ask "Do you want to proceed?"; a hand-typed `brew upgrade` still asks |
| `dotpush <message>` | Commits and pushes all dotfile changes to GitHub in one command |
| `edit <file>` | Opens a file in CotEditor |

### Keyboard shortcuts & reference

See [SHORTCUTS.md](../SHORTCUTS.md).
