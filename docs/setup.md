# Setup

See [README.md](../README.md).

The three paste blocks for a fresh Mac are at the top of the README. This is the rest of the walkthrough: what each step runs, how to check the machine afterwards, and where the repo files live. What a managed setting does is in [Settings](settings.md). The by-hand checklist is [Manual steps](manual-steps.md). After a software update, hotkey pins, and AC sleep are in [Troubleshooting](troubleshooting.md). Hammerspoon modes are in [Modes](modes.md).

## What's in the repo

- `Brewfile` — Homebrew formulae and casks. Nothing is installed from the Mac App Store
- `fish/` — Fish shell config and functions
- `ghostty/` — Ghostty terminal config
- `karabiner/` — Karabiner-Elements config (directory-symlinked into `~/.config/karabiner`)
- `hammerspoon/` — Hammerspoon Lua automations (directory-symlinked into `~/.hammerspoon`; `init.lua` loads modules such as `external_slack.lua`, `finder_hotkey.lua`, and the menu-bar mode switcher `mode_switcher.lua` + `modes.lua`)
- `gitconfig` — Git user and behaviour settings
- `mise/` — pinned tool versions (Node 22)
- `lib/` — lists and helpers the scripts read. The file header has the format
- `checks/` — one section of `macconfig-check.sh` per file. `macconfig-check.sh` sources them
- `scripts/` — helpers the other scripts call. The file header has the format
- `launchagents/` — user LaunchAgent plists. Installed as regular files in `~/Library/LaunchAgents` (`@HOME@` in `WatchPaths` is replaced with `$HOME`; launchd does not expand `~` or `$HOME`)
- Scripts: `bootstrap.sh`, `install.sh`, `macos.sh`, `dock.sh`, `handlers.sh`, `prune-apps.sh`, `shell.sh`, `hostname.sh`, `macconfig-check.sh`, `check.sh`, `defaults-diff.sh` (see [Scripts](#scripts))
- `docs/` — this walkthrough, [settings](settings.md), [manual steps](manual-steps.md), [troubleshooting](troubleshooting.md), and [modes](modes.md)
- `tests/`, `hooks/` — unit tests (`tests/run-all.sh` discovers `tests/*.test.sh`) and the pre-push lint/test gate
- `SHORTCUTS.md` — keyboard-shortcut cheat-sheets

## Bootstrap

The three paste blocks are in [README](../README.md#1-bootstrap). Paste them again later: each of those steps skips work that is already done.

`bootstrap.sh` walks through `install.sh`, `shell.sh`, `hostname.sh`, `macos.sh`, `dock.sh`, `handlers.sh`, and `prune-apps.sh`, prompting before each. `install.sh` starts Hammerspoon when the app is installed and not already running. `dock.sh` applies the Desktop assignments after it pins the Dock apps. Both use the same helpers as `macconfig --fix` (`lib/safe-fixers.sh`). After `install.sh` it names any missing company app and, in a terminal, offers to open Fleet Self service. A missing company app is a warning, not a failed step. If one of the setup steps fails, bootstrap records it and keeps going, including the manual-steps list and the offer to walk through them. At the end it prints the failed steps and the log path, and exits with an error. It is safe to re-run. `--yes` skips the prompts; `--dry-run` previews every step.

## Logs and when something fails

Each run of `bootstrap.sh`, `install.sh`, and `brewsync` is copied to `~/Library/Logs/dotfiles/` (`bootstrap-YYYYMMDD-HHMMSS.log`, and the same shape for `install` and `brewsync`, for example `install-20260101-120000.log`). The path is printed when the run finishes. Logs older than 30 days are removed. The log is the script's own output. Your password is not written there.

Before the Brewfile is installed, setup checks that this Mac can reach github.com and formulae.brew.sh, that the Xcode Command Line Tools are installed (`xcode-select -p`, and it offers `xcode-select --install` when they are missing), that at least 10 GB is free, and that `brew doctor` is not reporting a serious problem. A harmless doctor note does not stop setup. A failed check stops early, before any install, and gives a plain explanation of what to fix.

If one Brewfile entry fails, that entry is tried once more (`brew install` for a tool, `brew install --cask --adopt` for an app) and the others still install. Anything still missing is printed with the Homebrew error, when there is one, and the exact command to install it. If the install step itself stops before it can name a package, setup says the Brewfile install failed and points at the log under `~/Library/Logs/dotfiles/`. `brewsync` prints the same failure and the log path, still upgrades and cleans up, and exits with an error. `--adopt` takes over an app that is already in `/Applications` instead of stopping because the app is already there.

A package installer that needs an admin password (Karabiner-Elements is one) asks for it once at the start when you are in a terminal and that cask still needs to be installed or upgraded. `brew bundle check` and `brew outdated --cask` are how setup decides. A pkg cask that is already installed and current does not ask, and does not print a warning. The password stays fresh until the script exits. A run that is not a terminal skips the prompt and says that those installers may fail. `brewsync` copies its output through `tee`, so the installer itself does not see the terminal. The fish function records whether this terminal was interactive before that pipe. Piping `brewsync`, or running it with stdin closed, is not a terminal, and the warning is expected. Do not run these scripts as root.

## Dotfiles & packages

> _Run first by `bootstrap.sh`; the command below runs only this step._

`install.sh` symlinks the configs into `~/.config` (and `~/.gitconfig`, `~/.hammerspoon`), renders the login LaunchAgents into `~/Library/LaunchAgents` (`scripts/install-launchagent.sh` replaces `@HOME@` with `$HOME`, then bootout/bootstraps the job), installs the Brewfile, starts Hammerspoon if that cask is installed and the app is not already running (`open -g -a Hammerspoon`, the same helper as `macconfig --fix`), trusts the `mise` config, and enables the pre-push hook. The start happens after the `hammerspoon/` symlink and the Brewfile install. Idempotent and safe to re-run — it backs up any real file already in the way of a symlink rather than clobbering it. A second run does not reinstall Brewfile entries that are already present, and it does not open Hammerspoon again when it is already running. `--dry-run` describes those steps, including the Hammerspoon start, and changes nothing. The run log is `~/Library/Logs/dotfiles/install-YYYYMMDD-HHMMSS.log`.

```bash
~/.dotfiles-mac/install.sh
```

## Apps not in the Brewfile

> _Manual — no script installs these; do them by hand._

Homebrew formulae and casks come from the Brewfile. No apps currently come from the Mac App Store, because this Mac can't sign in with a personal Apple ID. Company apps come from Fleet Self service. The README names these three sources without listing each app.

These are not in those lists. Set them up by hand after bootstrapping:

- **Cursor Nightly** — download and install it from the [Cursor Nightly download page](https://cursor.com/nightlydownload), as a separate app. The Brewfile installs only the stable Cursor, so the stable build and Nightly sit side by side.
- **YouTube Music** — a Chrome app. In Chrome, open `music.youtube.com`, then click the install icon in the address bar (or **⋮ menu → Cast, save, and share → Install page as app**).
- **WhatsApp Web** — a Safari web app. The company's app policy blocks the WhatsApp app, so this is the website instead. In Safari, open `https://web.whatsapp.com` (a normal page, not a blank tab or a Private window), then **File → Add to Dock…**. Keep the name "WhatsApp Web" and the WhatsApp icon. On the Android phone, WhatsApp → ⋮ → Linked devices → Link a device, and scan the QR code. Linking the phone can't be checked from this repo. The click-by-click list is manual step `whatsapp-web`.

Company apps are the names in `lib/mdm-apps.list`. Zoom and 1Password are required, and so is every other name in that list. Install each one from Fleet Self service, not Homebrew. Fleet Desktop, the menu-bar app, has a My device item. Choose Self service there. The page needs company single sign-on, so nothing in this repo installs those apps unattended, and it does not call the Fleet API.

Okta Verify is an App Store copy owned by `root:wheel` (id 490179405). `mas` cannot upgrade that copy (`No downloads initiated for ADAM ID 490179405`), which breaks `brewsync`, so it stays out of the Brewfile. The 1Password desktop app is company-managed too. Its CLI (`1password-cli` / `op`) stays in the Brewfile. In the app, turn on Settings → Developer → Integrate with 1Password CLI, then run `op signin` once in a terminal.

1Password for Safari and Okta Extension App are not in the Brewfile and not in `lib/mdm-apps.list`. This Mac can't sign in to the App Store with a personal Apple ID, and it isn't known whether Fleet installs those Safari extensions. They are left out so a missing copy does not raise a warning.

Right after `install.sh`, `bootstrap.sh` checks that list. In a terminal it names each missing app and asks: Open Fleet Self service to install them now? Answering yes opens the self-service page. The address is `https://<fleet host>/device/<device id>/self-service`. The host is the MDM server from `profiles status -type enrollment`, or `cursor.cloud.fleetdm.com` when that line is missing. The device id is read from `/opt/orbit/identifier` on this Mac. It is not stored in the repo, and setup does not print it. `bootstrap.sh` copies its output into the setup log, so printing the id would save it there. When that file is missing, setup opens Fleet Desktop instead, or prints the menu path: Fleet Desktop menu bar → My device → Self service. Press Enter after installing. Setup checks again and says which apps are present and which are still missing. A miss is a warning, and setup continues. A run that is not a terminal, or `bootstrap.sh --yes`, names the missing apps and prints how to install them, and does not wait. `macconfig` and `macconfig --fix` ask the same question in a terminal. The result stays a warning. `--fix` does not install the apps.

These are also in the [manual steps](manual-steps.md) checklist (`manualsteps`, or `scripts/manual-steps.sh`). Do them before running `dock.sh`, or it'll skip them — `bootstrap.sh` flags any not-yet-installed Dock app before its Dock step, so you can install them first (or re-run `dock.sh` afterwards). Re-running `dock.sh` also applies that app's Desktop pin. A pin for an app that is still missing is not written.

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

Pin the apps to the Dock in order, then apply the Desktop assignments in `lib/desktop-bindings.list` (idempotent; the Dock apps use `dockutil` from the Brewfile). The Desktop step is `lib/safe-fixers.sh`, the same helper `macconfig --fix` uses: it runs `lib/desktop-bindings.py --apply`, backs up `com.apple.spaces`, writes `app-bindings`, and restarts the Dock only if a pin changed. `--list` and `--dry-run` print the Dock apps and those pins and change nothing.

```bash
~/.dotfiles-mac/dock.sh --list      # preview the apps, their order, and the Desktop pins
~/.dotfiles-mac/dock.sh --dry-run   # same preview; change nothing
~/.dotfiles-mac/dock.sh             # apply
```

Left to right, the order is Slack, WhatsApp Web, Granola, Google Chrome, Ghostty, CotEditor, Cursor, Cursor Nightly, Grok Bot, Spotify, YouTube Music. WhatsApp Web is the Safari web app from the manual step above (`~/Applications/WhatsApp Web.app`). If that app is not there yet, `dock.sh` skips it and says it is missing because the manual step hasn't been done. The other apps are still pinned. That missing app's Desktop pin is not written. Run `dock.sh` again after the manual step.

Slack, WhatsApp Web and Granola are Desktop 1. Chrome is Desktop 2. Cursor, Cursor Nightly and Grok Bot are Desktop 3. Spotify and YouTube Music are Desktop 4. Ghostty and CotEditor are not assigned. WhatsApp Web's bundle id is read from the app's Info.plist (`@APP@` in `lib/desktop-bindings.list`), so the UUID Safari generates is not stored in the repo. If the app is missing, that pin is reported as not set up yet and is not written.

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

The `duti` command can return before macOS shows the new app, especially when that app was just installed. The script checks every half second for up to 20 seconds, and tries the set once more if it still has not changed. When duti accepted the change and macOS has not caught up, that is a warning and setup keeps going. Run macconfig later to confirm. An actual duti error still fails that extension.

`.html` is not in that list. It is `public.html`, and setting it switches the default web browser. The fixer refuses `html` / `htm` / `xhtml`, `public.html` / `public.xhtml`, and any URL scheme. `.plist` is also set on `com.apple.property-list` and `com.apple.xml-property-list`, because `duti -x plist` follows `com.apple.property-list`. `.fish` often has no declared file type, so `duti` fails with error -50 on a dynamic UTI. That is a warning and is skipped, and the check does not call it drift. The row stays, so once some app declares a type for `.fish` the next run sets CotEditor.

## Unwanted apps (GarageBand, iMovie, Pages)

`prune-apps.sh` removes App Store apps listed in `lib/unwanted-apps.list` (idempotent; needs sudo). System apps like Music/Photos can't be deleted; GarageBand, iMovie, and Pages can. `macconfig-check.sh` drifts if they reappear.

Nothing in this repo is installed from the Mac App Store. This Mac can't sign in with a personal Apple ID, so the Brewfile has no `mas` app lines. Company apps are `lib/mdm-apps.list`, installed from Fleet Self service, not the Brewfile.

```bash
~/.dotfiles-mac/prune-apps.sh --dry-run   # preview
~/.dotfiles-mac/prune-apps.sh             # remove
```

## Quiet Apple apps (containment)

System apps (Music, Photos, News, …) can't be deleted (SIP). This repo contains them where scripting is reliable. The list is in [Settings](settings.md#quiet-apple-apps-containment).

## Keyboard / Dictation / Fn

**Goal:** hold-Fn/Globe must never start the mic (Dictation / Apple Intelligence). The scripted settings and the Karabiner rules are in [Settings](settings.md#keyboard-dictation-fn). What a macOS Software Update does to these hotkeys, and how to reload a LaunchAgent on this Mac, is in [Troubleshooting](troubleshooting.md#after-a-macos-software-update).

## Hammerspoon

[Hammerspoon](https://www.hammerspoon.org/) (Brewfile cask `hammerspoon`) runs small Lua automations. `hammerspoon/` → `~/.hammerspoon/` as a **directory** symlink (`lib/links.list`), so `init.lua` and its sibling modules load straight from the repo. `init.lua` loads the modules listed in `MODULES`. Add new automations as their own `*.lua` file there. It also sets: start at login, menu-bar icon only (no Dock icon), no crash-report upload, and loads `hs.ipc` so the `hs` CLI works. After that symlink and the cask install, `install.sh` runs `open -g -a Hammerspoon` when the app is installed and not already running (same helper as `macconfig --fix`). A second run leaves it alone when it is already running. `--dry-run` describes that start and does not open the app.

What `external_slack.lua` and `finder_hotkey.lua` do is in [Modes](modes.md#slack-on-the-arzopa-monitor). Accessibility is manual step `hammerspoon-ax` in [Manual steps](manual-steps.md).

## Modes (menu-bar switcher)

A Hammerspoon menu-bar dropdown switches between three modes. Switching is **manual only**: no hotkey, no automatic triggers. The modes, the safety rails, and the Focus Shortcuts are in [Modes](modes.md).

## App settings as code (Ghostty, Raycast)

Ghostty is fully in the repo. Raycast is partly readable. Logi Options+ is checked and never written. What each one does is in [Settings](settings.md#app-settings-as-code-ghostty-raycast).

## macOS defaults

> _Run by `bootstrap.sh`; the commands below run only this step._

A full `macos.sh` applies the rows in `lib/macos-defaults.list`, then Dictation hotkey 164, Quick Note hotkey 190, Game Overlay hotkey 260, Spotlight hotkey 64, the Services shortcuts in `lib/services-off.list`, CotEditor theme/font, Finder sidebar Recents, Finder Favorites (read only), the Show Finder shortcut, power settings, the built-in display's More Space mode, and the ARZOPA portable monitor when it is plugged in.

```bash
~/.dotfiles-mac/macos.sh --dry-run   # preview every decision, write nothing
~/.dotfiles-mac/macos.sh             # apply
```

A full run re-asserts a matching list row. `macos.sh --only` (what `macconfig --fix` calls) leaves a match alone. Hotkeys 64 and 260, and the Services list, are written only when the value differs, including on a full run. What each row does is in [Settings](settings.md#macos-defaults). Run `macos.sh --list` to see the exact set of settings it manages (printed as a Markdown table).

## Verifying the setup

> _Standalone tool — not run by `bootstrap.sh`; run it whenever you want to check for drift._

By default `macconfig-check.sh` is read-only (see [Read-only vs `--fix`](#read-only-vs---fix-self-healing-drift) for the opt-in self-healing mode): it reports drift vs the repo (symlinks, Brewfile + undeclared extras, defaults, Dock, shell, hostname, handlers, unwanted apps, Dictation/Karabiner/Hammerspoon/Login Items/Recents/CotEditor/Ghostty config/Logi Options+/Modes/Notifications/`*.app.back`, FileVault / pending updates, …) and ends with the [manual steps](manual-steps.md): failed automated checks are warnings (not drift), and steps with no reliable check show as `info` lines, counted as "to check by hand" in the summary. A step an earlier section already reported is one line in its numbered place. How that `checked above under` line works is in [Manual steps](manual-steps.md). Exits non-zero on drift — run after macOS updates:

```bash
macconfig
macconfig --health-json   # same checks, JSON summary only (for the weekly health note)
macconfig --fix           # also repair SAFE drift, re-check, list Fixed / Needs Paul
macconfig --reset-folder-views --dry-run   # list the per-folder Finder views it would clear
macconfig --reset-folder-views             # clear them (delete .DS_Store under ~) and restart Finder
~/.dotfiles-mac/macconfig-check.sh   # the same script, without fish
```

`macconfig` is a fish function, installed with the others in `fish/functions/`. It runs `macconfig-check.sh` from any directory and passes every argument through (`macconfig --fix`, `macconfig --no-color`, and so on). `check.sh` at the repo root execs `macconfig-check.sh` with the same arguments, stdin, and exit status, so `~/.dotfiles-mac/check.sh --fix --no-color` still works.

It ends with a short summary (coloured on a terminal: zero counts dimmed, drift red and warnings yellow when above zero; plain text with `--no-color` or when piped):

```
Summary
  ✔ ok           138 / 139
  ✖ drift          0
  ⚠ warnings       1
  ✋ by hand      20   (manualsteps list)
  1 needs attention (1 warning)
    - warn   Mac health: disk: only 12 GB free (8%) on Data (Needs Paul)
```

The verdict is `All good` when there's no drift and no warning, and in that case nothing follows it. Otherwise the verdict is followed by one indented bullet per outstanding drift or warning: the section, a short reason (what was measured against what was expected), and a hint — `fix: <id>` when `./macconfig-check.sh --fix` can repair it, `manual step` for a manual-step warning, otherwise `Needs Paul`. Long reasons are cut so the line stays within 100 columns. Drift bullets are red and warning bullets yellow on a terminal; `--no-color`, `NO_COLOR`, or a pipe leaves them plain. By-hand `info` lines stay in the by hand count, and they are not part of the ok total. A `checked above under` line is explained in [Manual steps](manual-steps.md). It is not in the ok, drift, warning, or by-hand totals, and `--health-json` is unchanged. The ok line is how many checks passed, over how many checks applied. A check that does not apply still prints an info line, and that line is in neither number and not in the by-hand count. That is an unplugged ARZOPA monitor, a closed lid or a panel size this repo does not list, a desktop pin for an app that is not installed, and Tailscale's Open at Login when Tailscale itself is not installed. When every check that applied has passed, the two ok numbers match. With `--fix` the bullets are what's still outstanding after the fixes. If some of the issues are SAFE to repair, a `→ run ./macconfig-check.sh --fix to repair N safe item(s)` line appears above the verdict. With `--fix` the summary also shows `↻ fixed` (`↻ would fix` on a dry run) and `☞ needs Paul`, and drift / warnings are the counts left after the fixes (`(was N before --fix)`). The summary is for people. Scripts and routines should read `--health-json`. The field names are in `macconfig-check.sh`.

### Read-only vs `--fix` (self-healing drift)

`macconfig-check.sh` on its own **never changes anything**. `macconfig-check.sh --fix` runs the same checks, then repairs only the drift that is classed **SAFE**, re-runs the checks to confirm each fix stuck, and ends with two lists: **Fixed** and **Needs Paul**. Anything that didn't stick moves to Needs Paul, with the reason.

```bash
~/.dotfiles-mac/macconfig-check.sh --fix --dry-run   # show what would be fixed; change nothing
~/.dotfiles-mac/macconfig-check.sh --fix             # apply the SAFE fixes, re-check, report
~/.dotfiles-mac/macconfig-check.sh --fix --health-json   # JSON, plus fixed[] / needs_paul[] (would_fix[] on a dry run)
```

The split lives in `lib/autofix.list`. The header names the fixer classes, and each row says what that id covers. A check sets `fixid <id>` in `checks/*.sh`. `macconfig-check.sh` sources those files. `tests/autofix.test.sh` keeps the tags and the list in sync. A SAFE fix reuses the existing setter. Every fix is idempotent and logged to `~/Library/Logs/com.pdone.check-fix.log`. With `--fix` the exit status is the drift left after the fixes.

SAFE is a reversible preference write. Needs Paul is reported and not written: Homebrew, the Dock layout, URL schemes, hostname, the login shell, sudo, and anything the list marks PAUL. Which fixer class is allowed is in [AGENTS.md](../AGENTS.md#1-scripted-and-checked).

### Mac health

`macconfig-check.sh`'s **Mac health** section adds read-only, timeout-guarded signals. Problems are warnings, never drift; anything that can't be read without sudo or Full Disk Access becomes an `info` (check by hand) line. The Mac health thresholds (`HEALTH_*`) live at the top of `checks/health.sh`. `macconfig-check.sh` presets `HEALTH_CRASH_DAYS` so `--health-json` has a value when that section is skipped:

| Signal | Source | Warns when |
|------|------|------|
| Battery | `system_profiler SPPowerDataType` (fallback `ioreg -rn AppleSmartBattery`) | condition isn't Normal, or maximum capacity < 80% (ok line shows capacity and cycle count) |
| Disk | `df -k /System/Volumes/Data` | free space < 50 GB or < 15% |
| Uptime | `sysctl kern.boottime` | > 14 days since the last restart |
| Memory | `sysctl vm.swapusage`, `kern.memorystatus_vm_pressure_level`, `memory_pressure -Q` | swap in use > 8 GB, or memory pressure critical |
| Storage hogs | `du -sk` of `~/Library/Caches`, Docker Desktop's `Docker.raw` (allocated size), `brew --cache`, Xcode DerivedData (if present) | Caches > 20 GB, Docker > 60 GB, brew cache > 5 GB (`brew cleanup --prune=all`), DerivedData > 20 GB; each warning names the fix |
| Security basics | `socketfilterfw --getglobalstate`, `spctl --status`, `csrutil status`, launchd jobs `com.openssh.sshd` / `com.apple.screensharing` / `com.apple.smbd` or a listener on 22 / 5900 / 445 (no sudo), `sysadminctl -screenLock status` | Firewall, Gatekeeper or SIP off; Remote Login, Screen Sharing or File Sharing on; password not required immediately after sleep / screen saver. Firewall and screen lock may be MDM-managed |
| MDM | `profiles status -type enrollment`, launchd `com.fleetdm.orbit` (Fleet agent: orbit, plus osquery and Fleet Desktop under `/opt/orbit`) | not enrolled, or the Fleet agent (orbit) isn't running |
| Crashes | `lib/crash-reports.py` over `/Library/Logs/DiagnosticReports` and `~/Library/Logs/DiagnosticReports` (+ `Retired/`), last 7 days | any kernel panic (`*.panic` / bug_type 210), or ≥ 3 crashes (bug_type 309) of one app, named. Non-fatal `ExcUserFault_*` reports are counted as faults, not crashes |
| Background jobs | `launchctl print gui/<uid>/<label>` for every plist in `launchagents/`; Hammerspoon running (Hammerspoon section) | an agent isn't loaded or its last exit code isn't 0 (each pin agent's "loaded" and "plist matches" state stays a drift check in its own section) |
| Dotfiles in sync | `git status --porcelain` (gitignored `.agent-logs/` doesn't count) and `git rev-list HEAD...origin/main` | uncommitted / untracked changes, or ahead of / behind `origin/main`. **No network:** it compares with `origin/main` as of the last fetch or push (shown in the ok line), so `macconfig-check.sh` stays offline and read-only; run `git fetch` first if you need it fresh |
| Login / background items | `lib/btm-login-items.py --audit lib/login-items-allow.list` | an enabled item is neither on `lib/login-items-allow.list` nor approved by an MDM Service Management rule (Fleet pushes these; the helper reads them from the BTM store), or a stale item points to an app that no longer exists. An item whose team id is already on an MDM rule is not told to turn off: add it to the allow list |

FileVault and pending software updates are covered under **Security hygiene**. To accept a new login item, add a `team|`, `bundle|`, `label|`, `label-prefix|` or `app|` row to `lib/login-items-allow.list` (format in its header). An `app|` row is the full path of one app under Open at Login, for an app whose bundle id is different on each Mac, such as the WhatsApp Web Safari web app at `~/Applications/WhatsApp Web.app`. Other Safari web apps are still reported. To see every enabled item and how it's classified: `python3 lib/btm-login-items.py --audit lib/login-items-allow.list`. Reading the BTM store needs Full Disk Access for the terminal (Ghostty) or agent running `macconfig-check.sh`.

`./macconfig-check.sh --health-json` prints only JSON, with the same exit status. The field names are in `macconfig-check.sh`. The weekly health note is built from that JSON.

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

> _Manual — no script can do these. A standalone `install.sh` prints the full checklist. Under bootstrap, `DOTFILES_BOOTSTRAP=1` suppresses that print, and `bootstrap.sh` prints the steps that are not set yet, or that can't be checked (`manualsteps pending`). On a terminal, both offer to walk through them._

The checklist, the `NOTSET:` / `MANUAL:` legend, and the commands are in [Manual steps](manual-steps.md). That file is generated from `lib/manual-steps.list` by `scripts/render-manual-steps-doc.sh`.

## Usage & reference

### Scripts

| Script | What it does, and when to run it |
|------|------|
| `bootstrap.sh` | Guided full setup: runs `install.sh`, `shell.sh`, `hostname.sh`, `macos.sh`, `dock.sh`, `handlers.sh`, `prune-apps.sh` in order, prompting before each. Right after `install.sh`, names any missing company app and, in a terminal, offers to open Fleet Self service. A missing company app is a warning, not a failed step. A failed step is recorded and the later steps still run, including the manual-steps list. The end of the run names any failed steps and the log, then exits with an error. `--dry-run` previews all steps, `--yes` skips prompts. Idempotent. |
| `install.sh` | The dotfiles layer of a fresh-machine setup: preflight, symlinks, rendered login LaunchAgents, Brewfile, `mise` trust, and enabling the pre-push hook; ends with the manual-steps checklist. Does *not* set shell/hostname/defaults/Dock (those are `bootstrap.sh`). Before `brew bundle` it checks the network, the Xcode Command Line Tools, free disk (10 GB), and serious `brew doctor` issues. A failed Brewfile entry is retried once (`brew install`, or `brew install --cask --adopt` for an app) and does not stop the others. Anything still missing is named, with the Homebrew error when there is one and the command to install it, and the summary points at `brewsync`. Writes `~/Library/Logs/dotfiles/install-YYYYMMDD-HHMMSS.log`. Also `mkdir -p ~/Pictures/Screenshots` (the screenshot save location; existing files are not moved). Renders `launchagents/*.plist` into `~/Library/LaunchAgents` (`@HOME@` → `$HOME`) and bootout/bootstraps each job. Safe to re-run — repoints symlinks, backs up any real file in the way of a symlink, and does not reinstall a Brewfile entry that is already there. |
| `scripts/brew-bundle-install.sh` | Install the Brewfile. `install.sh` and `brewsync` call it. Retries each missing entry once, adopts an existing app when Homebrew supports `--adopt`, and names anything still missing. `--install-homebrew` installs Homebrew when `brew` is not on PATH. |
| `macconfig-check.sh` | Read-only drift check vs the repo (incl. Brewfile extras, FileVault, pending software updates, Mac health, and the manual-steps checks). A missing company app (`lib/mdm-apps.list`) is a warning. In a terminal the check offers to open Fleet Self service and does not install the app. `--health-json` prints a JSON summary instead. `--fix` (optionally with `--dry-run`) also applies the SAFE fixes from `lib/autofix.list`, re-checks, and lists Fixed / Needs Paul. `--fix` does not install company apps. Run any time (especially after a macOS update), or use the `macconfig` fish function. Exits non-zero on drift. Login Items + Finder Recents need Full Disk Access for the terminal you run it from (Ghostty); Grok Bot already has this for the weekday 9am check. |
| `check.sh` | Shim that execs `macconfig-check.sh` with the same arguments, stdin, and exit status. Kept so existing callers (the scheduled `~/.dotfiles-mac/check.sh --fix --no-color`, plus muscle memory) stay valid. |
| `macos.sh` | Apply managed `defaults` plus Dictation hotkey 164, Quick Note hotkey 190, Game Overlay hotkey 260, Spotlight hotkey 64, the Services shortcuts in `lib/services-off.list`, CotEditor theme/font, Finder sidebar Recents, the Show Finder shortcut, power settings (sudo `pmset`, skipped when sudo isn't available or isn't wanted), the built-in display's More Space mode, and the ARZOPA portable monitor when it is plugged in (`displayplacer`; other displays unchanged). A full run re-asserts a matching list row. `--only` leaves a match. Hotkeys 64 and 260, and Services, are written only when the value differs. Dark mode is also turned on live with System Events when it is not already on. A changed trackpad setting is reloaded with `activateSettings -u` when that tool is present. Finder Favorites are checked from the sidebar file and not changed. The Tahoe Night wallpaper stays by hand. `--dry-run` / `--list`. `--only <id>` (repeatable) and `--yes` (restart without prompting) are what `macconfig-check.sh --fix` uses. Creates `~/Pictures/Screenshots` with `mkdir -p` before writing `com.apple.screencapture location`. Idempotent. |
| `dock.sh` | Pin the Dock apps in order, then apply `lib/desktop-bindings.list`. Run after the apps are installed and whenever you edit `lib/dock-apps.list`. `--list` previews the apps and the Desktop pins. Idempotent; needs `dockutil`. |
| `handlers.sh` | Set URL-scheme defaults (`lib/url-handlers.list`) and Finder file defaults (`lib/file-handlers.list`, role `all`). `--dry-run` / `--list`. Idempotent; needs `duti`. |
| `prune-apps.sh` | Remove apps listed in `lib/unwanted-apps.list` (GarageBand, iMovie, Pages). `--dry-run` / `--list`. Idempotent; needs `sudo` / `mas`. |
| `shell.sh` | Make fish the login shell. Run once on a fresh machine (see "Set login shell"). Idempotent; sudo/`chsh` only if needed. |
| `hostname.sh` | Set HostName/LocalHostName/ComputerName. Run once on a fresh machine (see "Set Hostname"). Idempotent; sudo only if a name differs. |
| `defaults-diff.sh` | Discover which `defaults` key backs a System Settings toggle, to add to `lib/macos-defaults.list`. Run when you want to manage a new setting. Read-only. |
| `scripts/reset-folder-views.sh` | Delete the view each folder saved for itself (`.DS_Store` files under your home folder, Desktop included) and restart Finder, so every folder uses the default Sort By Name. Custom views and icon positions in those folders are lost. Skips `~/Library`, `~/.Trash`, hidden folders, `node_modules`, app and Photos/Music library bundles, other volumes, and symlinks. `--dry-run` lists what it would delete. Run it with `macconfig --reset-folder-views`; it never runs on its own. See [Troubleshooting](troubleshooting.md#a-finder-folder-is-not-sorted-by-name). |
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
- **Desktop assignments:** edit `lib/desktop-bindings.list` (`1`..`N` = Desktop N on the main display, `none` = not assigned), then run `macconfig --fix`. The order and the Desktop 1–4 map are in [Dock](#dock).
- **URL handlers:** edit `lib/url-handlers.list`, then run `handlers.sh`.
- **Finder file handlers:** edit `lib/file-handlers.list` (extension, app, bundle id; optional `unpinnable` or `uti:…`; role is always `all`), then run `macconfig-check.sh --fix` (or `handlers.sh` on a fresh setup). Do not add `html` — it switches the default browser.
- **Display auto-brightness:** checked, not written. System Settings → Displays. See [Settings](settings.md#macos-defaults).
- **Power:** `macos.sh` runs the sudo `pmset` commands that are still wrong. `--fix` does not. See [Troubleshooting](troubleshooting.md#ac-idle-sleep).
- **Built-in display More Space:** the mode list is `lib/display-resolution.list`. `macos.sh` and `macconfig --fix` set it. See [Settings](settings.md#macos-defaults).
- **ARZOPA portable monitor:** the same list and the same command, when the monitor is plugged in. Slack on that screen is in [Modes](modes.md#slack-on-the-arzopa-monitor). See [Settings](settings.md#macos-defaults).
- **Notifications:** edit `lib/notifications-off.list` or `lib/notifications-reviewed.list`. The check only reads. If the bit moves, change `ALLOW_NOTIFICATIONS_BIT` in `lib/notification-prefs.py`. See [Notifications](settings.md#notifications).
- **Account picture:** the hash is `lib/user-picture.sha256`. The check only reads. See [Settings](settings.md#macos-defaults).
- **Karabiner background:** checked, not written. See [Settings](settings.md#keyboard-dictation-fn).
- **Finder sidebar rows:** edit `lib/finder-sidebar-rows.list`. The check only reads. See [Settings](settings.md#macos-defaults).
- **Unwanted apps:** edit `lib/unwanted-apps.list`, then run `prune-apps.sh`.
- **Login LaunchAgents:** edit `launchagents/*.plist`. `WatchPaths` uses `@HOME@`, not `~` or `$HOME` (launchd expands neither). `install.sh` or `macconfig-check.sh --fix` renders the plist into `~/Library/LaunchAgents` and, when the installed file differs, reloads it with `launchctl bootout` then `bootstrap`. These are regular files, not symlinks.
- **Services kept off:** edit `lib/services-off.list` (one `pbs` `NSServicesStatus` key per line), then run `macos.sh` or `macconfig --fix`. The quoting rules are in [Settings](settings.md#keyboard-dictation-fn).
- **Manual steps:** add a row to `lib/manual-steps.list` (with a read-only check if one is reliable), then regenerate [docs/manual-steps.md](manual-steps.md) with `scripts/render-manual-steps-doc.sh` (it runs `scripts/manual-steps.sh list --markdown`).
- After any change, run `macconfig` (or `./macconfig-check.sh`) to confirm the machine still matches the repo.

### Fish functions

| Function | Description |
|------|------|
| `macconfig` | Checks this Mac's config settings against the repo (`macconfig-check.sh`). Arguments pass through: `macconfig`, `macconfig --fix`, `macconfig --no-color`, `macconfig --reset-folder-views --dry-run` |
| `manualsteps` | By-hand settings (`scripts/manual-steps.sh`). No arguments runs `check`. Arguments pass through: `manualsteps list`, `manualsteps open`, `manualsteps open --all`, `manualsteps --help` |
| `brewsync` | Installs, upgrades, and cleans up Homebrew packages from the Brewfile. A missing entry is retried once, and an app already in `/Applications` is adopted. If that install step stops before it can name a package, `brewsync` says so and prints the log path, then still upgrades and cleans up, and exits with an error. Sets `HOMEBREW_NO_ASK` for that run only, so Homebrew 7 does not ask "Do you want to proceed?"; a hand-typed `brew upgrade` still asks. A pkg cask (Karabiner-Elements) asks for an admin password only when it still needs an install or an upgrade, and only in a terminal. Writes `~/Library/Logs/dotfiles/brewsync-YYYYMMDD-HHMMSS.log` |
| `dotpush <message>` | Commits and pushes all dotfile changes to GitHub in one command |
| `edit <file>` | Opens a file in CotEditor |

### Keyboard shortcuts & reference

See [SHORTCUTS.md](../SHORTCUTS.md).
