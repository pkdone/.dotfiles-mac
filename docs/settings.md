# Settings

See [README.md](../README.md).

This is what each managed setting does, and why. Applying them is the [setup walkthrough](setup.md). The by-hand list is [Manual steps](manual-steps.md). After a software update, hotkey pins, and AC sleep are in [Troubleshooting](troubleshooting.md).

## Quiet Apple apps (containment)

System apps (Music, Photos, News, …) can't be deleted (SIP). This repo contains them where scripting is reliable:

- **URL handlers** → Chrome (`handlers.sh` / `lib/url-handlers.list`)
- **GarageBand / iMovie / Pages** removed (`prune-apps.sh`)
- **Photos auto-open on device connect** Off (`com.apple.ImageCapture disableHotPlug` in `lib/macos-defaults.list`)
- **Menu bar:** clock, mode icon, battery percentage, Wi-Fi, Bluetooth, Control Centre, and the third-party icons that stay (Tailscale, 1Password, Granola, Hammerspoon, Kandji/company agents). Spotlight, Focus, Now Playing and Voice Control are hidden (`@host/com.apple.controlcenter` = `8`, Don't Show). Bluetooth stays in the menu bar (`2`, Show in Menu Bar). Battery percentage is On (`BatteryShowPercentage`, boolean; `defaults read` prints `1`). `macos.sh` / `macconfig-check.sh` check those rows; `macconfig --fix` repairs them and restarts ControlCenter. Karabiner's own menu bar icon stays hidden. Raycast, Logi Options+ and Docker are Off under System Settings → Menu Bar → Allow in the Menu Bar (manual step `menubar-third-party-hide`; Raycast's own toggle isn't scriptable)
- **Dock minimize and bounce:** windows minimize into the application icon (`com.apple.dock minimize-to-application` = true) and opening an app does not bounce the icon (`no-bouncing` = true). `macos.sh` / `macconfig-check.sh`; `macconfig --fix` repairs them and restarts Dock
- **Finder sidebar Recents** Off, **icon view 72/13**, **show all filename extensions** On, **status bar** On, **sidebar icon size** Large, and **CotEditor** theme **Anura (Dark)** + monospaced font via `macos.sh` / `macconfig-check.sh`
- **Finder and Trash tidy:** remove Trash items after 30 days (`FXRemoveOldTrashItems`), search the current folder (`FXDefaultSearchScope` = `SCcf`), keep folders on top (`_FXSortFoldersFirst`), and no `.DS_Store` on network volumes (`com.apple.desktopservices DSDontWriteNetworkStores`; the domain is created by the first write). `macos.sh` / `macconfig-check.sh`; `macconfig --fix` repairs them and restarts Finder
- **Window tiling (macOS 15+):** drag a window to the left or right edge to tile (`com.apple.WindowManager EnableTilingByEdgeDrag` = true; unset on this Mac, which is the system default On) and no gap between tiled windows (`EnableTiledWindowMargins` = false; `defaults read` prints `0`). `macos.sh` / `macconfig-check.sh`; `macconfig --fix` repairs them. `restart` is empty, so a repair restarts no process. Shortcuts are in [SHORTCUTS.md](../SHORTCUTS.md)
- **Desktop widgets and Stage Manager:** widgets hidden on the desktop and in Stage Manager (`StandardHideWidgets` and `StageManagerHideWidgets` = true; Show Widgets → On Desktop and In Stage Manager off) and Stage Manager off (`GloballyEnabled` = false). `macos.sh` / `macconfig-check.sh`; `macconfig --fix` repairs them through the `defaults` row in `lib/autofix.list`. `restart` is empty, so a repair restarts no process. Click wallpaper to reveal desktop (`EnableStandardClickToShowDesktop`) is not pinned
- **Login Items:** `macconfig-check.sh` drifts if ChatGPT, Gemini, or GeminiAppLauncher are enabled at login (apps may stay installed; turn them **Off** in **System Settings → General → Login Items**)

Universal Links like `https://music.apple.com` may still open Apple apps — use Chrome when it matters.

## Keyboard / Dictation / Fn

**Goal:** hold-Fn/Globe must never start the mic (Dictation / Apple Intelligence).

**Scripted + checked** (`macos.sh` / `macconfig-check.sh`):
- Fn/Globe → **Do Nothing** (`AppleFnUsageType` = `0`)
- Dictation **Off**
- Symbolic hotkey 164 ("Start Dictation") pinned to **Right Command twice** — a *dummy* unused combo so Press 🎙️ / Fn never owns it. Do **not** use Right Command twice yourself; it would fire dictation if Dictation were on.
- Symbolic hotkey 190 ("Quick Note") disabled so Globe/Fn+Q does not open Notes (`enabled=0`, `type=standard`, unbound parameters).

What a macOS Software Update does to these hotkeys, and how to reload a LaunchAgent on this Mac, is in [Troubleshooting](troubleshooting.md#after-a-macos-software-update).

**Karabiner** (Brewfile cask `karabiner-elements`; `karabiner/` → `~/.config/karabiner/` as a **directory** symlink — Karabiner won't watch a file symlink):
- Fn/Globe only sets internal variable `pdone_fn` (never sent to macOS)
- While held: Fn+F → ⌃⌘F (fullscreen); Fn+F11 → Show Desktop; Fn+Delete → forward-delete; Fn+arrows → Home/End/PgUp/PgDn
- Dictation/microphone consumer keys swallowed; Finder Forward Delete → Move to Trash
- Top-row brightness/volume still work without Fn
- Menu bar icon hidden: `global.show_in_menu_bar` and `show_profile_name_in_menu_bar` are both `false` in `karabiner/karabiner.json` (the directory symlink's `~/.config/karabiner/karabiner.json`). `macconfig-check.sh` reads that file with python3 and drifts if either is not false. Restore is git (`karabiner-rules` in `lib/autofix.list`); `--fix` does not rewrite it
- `macconfig-check.sh` drifts if the dir symlink, Fn-kill rule, Finder Trash rule, or menu bar icon setting is missing

**Manual once (TCC / DriverKit):** Driver Extensions + Device Control and Data Access (Karabiner-Core-Service) — see [Manual steps](manual-steps.md) (`karabiner-driver`, `karabiner-ax`; `macconfig-check.sh` verifies the driver and the Core-Service grant). Allow in the Background is checked too: Karabiner-Core-Service and Karabiner-VirtualHIDDevice-Daemon must be enabled and allowed. Karabiner-Elements Privileged Daemons v2 may stay disabled. The check reads the same background-item records `sfltool dumpbtm` prints, and it does not change them. If those records cannot be read, it tries `sfltool dumpbtm` for a few seconds and, if that does not finish, leaves the step as info. Karabiner 16+ does not need Input Monitoring. If DriverKit never enables, work MDM/EDR may be blocking Team ID `G43BCU2T37`.

## App settings as code (Ghostty, Raycast)

**Ghostty: fully in the repo.** `ghostty/config` is symlinked to `~/.config/ghostty/config` (`lib/links.list`). `macconfig-check.sh` (the **Ghostty config** section) checks four things:

- the link
- that the repo file is valid (`ghostty +validate-config`)
- that no other file Ghostty loads overrides it (`~/Library/Application Support/com.mitchellh.ghostty/config` or `config.ghostty`, and `~/.config/ghostty/config.ghostty`)
- that Ghostty's effective config (`ghostty +show-config`) is exactly what the repo file alone produces

A broken link is restored by `macconfig-check.sh --fix`. An override file is reported but never deleted automatically.

**Raycast: partly readable.** Raycast keeps almost everything in an encrypted database (`~/Library/Application Support/com.raycast.macos/raycast-enc.sqlite`). The only setting readable from `defaults` is the launcher hotkey: `com.raycast.macos raycastGlobalHotkey` = `Shift-Control-Command-15`, where key code 15 is R. The manual-steps check for that step reads it automatically.

Clipboard History (Control+Command+V, 1-day history, 1Password and 1Password for Safari excluded) lives only in the encrypted database, so it stays **by hand**. Shift+Control+Command+F brings Finder to the front from Hammerspoon (`hammerspoon/finder_hotkey.lua`). If the Raycast backup being imported still has a Finder hotkey on Shift+Control+Command+F, unbind it in Raycast so it doesn't clash with Hammerspoon (manual step `raycast-finder-unbind`).

Raycast's supported backup is **Export Settings & Data**, a passphrase-encrypted `.rayconfig` file (Raycast → Settings → Advanced → Export, or Scheduled Backup). Restoring it is a GUI step: Import Settings & Data, then tick **Settings, Aliases & Hotkeys**. The export also holds clipboard history, AI chats, notes, MCP servers and extension settings (which can include tokens), so it is **never stored in this repo**. `*.rayconfig` is gitignored. Keep it in a synced folder via Scheduled Backup instead. Writing the hotkey back with `defaults write` isn't a supported restore (Raycast holds it in memory and in its database), so the step stays manual (`raycast-import` / `raycast-hotkey` in [Manual steps](manual-steps.md)).

**Logi Options+: checked, never written.** Logi Options+ keeps its settings as JSON inside a private SQLite database (`~/Library/Application Support/LogiOptionsPlus/settings.db`; the agent caches it and syncs it to the mouse). `lib/logi-settings.py` copies the database (plus its `-wal` / `-shm`) to a temp dir, reads the copy read-only, deletes it, and compares the MX Master 3S values (found by model `2b034`, not serial number) with `lib/logi-expected.list`: main wheel Natural + smooth + SmartShift, thumb wheel horizontal scroll + smooth, gesture button window navigation, pointer speed 0.12. The **Logi Options+** section of `macconfig-check.sh` reports drift as **Needs Paul** (`logi-settings` in `lib/autofix.list`; `--fix` never touches it), and a missing app, missing database or unreadable format as a warning (`logi-unreadable`), never a failure of the run. Restore is by hand in the app or from Logi's cloud backup (manual step `logi-cloud-backup`). Cloud backup itself stays **by hand**: the **Automatically backup all devices** toggle and the last-backup time aren't in any readable local file (the per-device `settings_backup_state_v2` flags in `settings.db` stay false with backup on), so there's nothing reliable to check. Manual step `logi-smooth-scrolling` uses the same helper (`logi:<id>` check).

## macOS defaults

> _Run by `bootstrap.sh`; the commands below run only this step._

A curated set of macOS `defaults` is applied by `macos.sh` (plus Dictation hotkey 164, CotEditor theme/font, Finder sidebar Recents, Finder Favorites, the Show Finder shortcut, power settings, and the built-in display's More Space mode):

```bash
~/.dotfiles-mac/macos.sh --dry-run   # preview every decision, write nothing
~/.dotfiles-mac/macos.sh             # apply
```

Safe to re-run: it reads and type-checks each setting first, then writes the desired value (re-asserting even when it already matches), skips any key whose stored type is unexpected (with a warning), and sets missing keys. Before the first actual change it backs up each affected domain to `backups/defaults-<timestamp>/`. UI restarts (Dock, Finder, menu bar) happen at the end only when something actually changed, after you confirm.

Dark mode is `NSGlobalDomain` `AppleInterfaceStyle` = `Dark`. `macos.sh` also tells System Events to turn dark mode on immediately when it is not already on, so a logout is not required. If System Events refuses (often a missing Automation permission), that is a warning and the default is still written. `macconfig --fix` uses the same path.

Power is the one `macos.sh` step that uses sudo. It runs only the `pmset` commands that are still wrong: AC sleep 0, AC display sleep 10 minutes, battery display sleep 2 minutes, and AC wake for network access. It is skipped when sudo isn't available (no passwordless sudo and no terminal) or isn't wanted (`--dry-run`, or you answer no at the prompt). Values that already match do not call sudo. `--yes` skips that confirmation and still will not hang waiting for a password when there is no terminal. Battery idle sleep is not changed. Closing the lid still sleeps the Mac. The check warns when one of those values differs, which is what a company MDM reset (Kandji) often does to the sleep timer. `--fix` does not run sudo. See [Troubleshooting](troubleshooting.md#ac-idle-sleep).

Trackpad rows in that list are tap to click (built-in trackpad, Bluetooth trackpad, and `com.apple.mouse.tapBehavior`), click pressure Light, secondary click in the bottom right corner, three-finger drag Off, tracking speed `0.6875`, Force Click and haptic feedback On (`ActuateDetents=1`, `ForceSuppressed=0`), natural scrolling On, swipe-between-pages Off, three-finger tap Off, and the 3/4/5-finger swipe and pinch gestures. The gesture keys are written for both the built-in trackpad and the Bluetooth trackpad. Secondary click stays the bottom-right corner (`TrackpadCornerSecondaryClick` = 2) and a right-side click stays off (`TrackpadRightClick` = 0). Each one sets `restart` to `logout`. When a value changes, `macos.sh` runs `activateSettings -u` when that tool is present, so the trackpad follows the new value without a logout. If it is missing or fails, the change is listed as needing a logout, and `bootstrap.sh` prints that list at the end of setup. `macconfig-check.sh` reads the same list, and `macconfig --fix` repairs drift through the `defaults` row in `lib/autofix.list` and uses the same reload. Look up & data detectors is checked (`com.apple.trackpad.forceClick` = 0) and not written. Mouse tracking speed and scrolling speed stay a check only, because writing them does not stick.

Finder and Trash tidy rows in that list remove Trash items after 30 days (`com.apple.finder FXRemoveOldTrashItems`), search the current folder (`FXDefaultSearchScope` = `SCcf`), keep folders on top (`_FXSortFoldersFirst`), and skip `.DS_Store` on network volumes (`com.apple.desktopservices DSDontWriteNetworkStores`). That domain may not exist until the first write; writing creates it. Those four set `restart` to `Finder`. The Tags group in the sidebar stays closed (`SidebarTagsSctionDisclosedState` = false; Apple's key is spelled that way). Screenshots and screen recordings save to `~/Pictures/Screenshots` (`com.apple.screencapture location`, stored as `@HOME@/Pictures/Screenshots` so apply and check expand `$HOME`), keep the floating thumbnail (`show-thumbnail` = true), use window capture (`style` = `window`), and leave video capture on (`video` = 1). macOS may store video capture as an integer or a boolean. Either one counts as on, so that difference is not drift, and `macconfig --fix` leaves an on value alone. `location` is the save folder for both screenshots and recordings. Those keys set `restart` to `SystemUIServer`. `install.sh` creates `~/Pictures/Screenshots` with `mkdir -p`. `macos.sh` does the same before it writes the location, including when `macconfig --fix` repairs that key. Existing screenshots are left where they are.

Finder sidebar Favorites are `lib/sidebar-favorites.list` (Applications, Desktop, Developer, Documents, Downloads, Movies, Music, Pictures). `macos.sh` and `macconfig-check.sh` read `~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.FavoriteItems.sfl4` (or `.sfl3`, or `.sfl2`, whichever file this Mac has) and compare the file favorites with that list. A match is left alone. A difference is a warning. Nothing writes the sidebar file: Homebrew has no `mysides` formula or cask, and editing that file directly is not reliable, so `macconfig --fix` does not change Favorites. The Tags group stays collapsed (`SidebarTagsSctionDisclosedState`; Apple spells it that way). Recents stays hidden. Shared at the top, AirDrop and iCloud Drive hidden, and the Locations rows (your home folder, Macintosh HD, Network, Trash) are checked when the sidebar files name them. A row the files do not name stays by hand. `ShowRecentTags` and `SidebarShowingiCloudDesktop` are not checked: their values on this Mac were not confirmed, so pinning them would warn on a good setup. `macconfig --fix` does not change the sidebar.

Show Finder is the menu shortcut Cmd-Ctrl-Shift-F (`com.apple.finder` `NSUserKeyEquivalents`, added with `-dict-add` so other menu shortcuts stay). Hammerspoon uses the same keys to bring Finder to the front from any app (`hammerspoon/finder_hotkey.lua`). Double-clicking a window's title bar fills the window (`AppleActionOnDoubleClick` = `Fill`). If the older minimize-on-double-click key is set, `macos.sh` deletes it.

The built-in display's More Space mode is set by `macos.sh` with `displayplacer` (Homebrew formula `displayplacer`) when that mode is listed for the panel in `lib/display-resolution.list` (14": `1800 x 1169`, 16": `2056 x 1329`). The current refresh rate is kept when a scaled mode at that rate exists. External displays are left on their current mode. A missing `displayplacer` or a missing mode is a warning and stays the manual step (System Settings → Displays). `macconfig --fix` uses the same path. An unlisted panel size, or no built-in panel, is left alone.

The desktop picture is Tahoe Night (Landscape). `macconfig-check.sh` looks for asset `CF6347E2-4F81-4410-8892-4830991B6C5A` in the wallpaper store and warns if it is absent. That picture is a wallpaper-catalog asset, not a file under `/System/Library/Desktop Pictures`, so System Events cannot select it. The wallpaper store is not written. `--fix` does not change the picture. Set it by hand in System Settings → Wallpaper.

Automatically adjust brightness stays by hand (System Settings → Displays). It needs an admin password, and the saved value is a root-owned file. `bootstrap.sh` names this step when it prints the manual steps, and the walk-through opens Displays. True Tone and Slightly dim the display on battery are left alone.

The account picture is the Dog. `macconfig-check.sh` hashes the JPEGPhoto on the user account (the same bytes as `dscl . -read /Users/$USER JPEGPhoto | tail -n +2 | xxd -r -p`) and compares it with `lib/user-picture.sha256`. A different picture is a warning. `--fix` does not change it.

Window tiling rows in that list turn on drag-to-edge tiling (`com.apple.WindowManager EnableTilingByEdgeDrag` = true) and turn tiled-window margins off (`EnableTiledWindowMargins` = false). On this Mac the edge-drag key is unset, which is the system default On, and margins read as `0` (boolean false). Both rows leave `restart` empty. WindowManager applies the domain live: writing the margins key moves windows that are already tiled, and the edge-drag key is read on the next drag, so `macos.sh` restarts no process for them. `macconfig-check.sh` reads the same list, and `macconfig --fix` repairs drift through the `defaults` row in `lib/autofix.list`. HideDesktop, drag-to-menu-bar, the Option-drag toggle, and Click wallpaper to reveal desktop (`EnableStandardClickToShowDesktop`) stay out of the list. Desktop pins in `lib/desktop-bindings.list` stay as they are.

Stage Manager and desktop widgets are three more `com.apple.WindowManager` rows. `StandardHideWidgets` = true and `StageManagerHideWidgets` = true hide widgets (System Settings → Desktop & Dock → Widgets → Show Widgets: On Desktop off, and In Stage Manager off). `GloballyEnabled` = false turns Stage Manager off. Those rows leave `restart` empty too. WindowManager applies the domain live, so `macos.sh` does not `killall Dock` (that reloads Spaces) or WindowManager. `macconfig --fix` repairs them through the same `defaults` row in `lib/autofix.list`.

Menu bar rows in that list hide Spotlight, Focus, Now Playing and Voice Control (`@host/com.apple.controlcenter` = `8`, Don't Show), keep Bluetooth in the menu bar (`Bluetooth` = `2`, Show in Menu Bar), and show the battery percentage (`BatteryShowPercentage` = true; `defaults read` prints `1` because the type is boolean). Each of those sets `restart` to `ControlCenter`, the same token Spotlight, Focus and Now Playing already use. `macos.sh` runs `killall ControlCenter` only when a value changed. `macconfig-check.sh` reads the same list, and `macconfig --fix` repairs drift through the `defaults` row in `lib/autofix.list`. The intended menu bar is the clock, the mode icon, battery percentage, Wi-Fi, Bluetooth and Control Centre, plus Tailscale, 1Password, Granola, Hammerspoon and Kandji/company agents. Wi-Fi is already shown and is not pinned here. Raycast, Logi Options+ and Docker are turned off by hand (manual step `menubar-third-party-hide`). Karabiner-Elements stays out of the menu bar via `karabiner.json`.

Dock behavior rows in that list minimize windows into the application icon (`com.apple.dock minimize-to-application` = true) and turn off the bounce when an app opens (`no-bouncing` = true; System Settings → Desktop & Dock → Animate opening applications Off). Both set `restart` to `Dock`, the same as icon size, recent apps, and Hot Corners. Icon size stays exactly `28`. A change restarts Dock. `macconfig-check.sh` reads the same list, and `macconfig --fix` repairs drift through the `defaults` row in `lib/autofix.list`. App order stays in `lib/dock-apps.list`.

Run `macos.sh --list` to see the exact set of settings it manages (printed as a Markdown table).

## Notifications

Per-app **Allow Notifications** is checked by the **Notifications** section of `macconfig-check.sh`. An app in `lib/notifications-off.list` whose Allow Notifications is on is a warning (**Needs Paul**). A third-party app (`com.apple.*` and `_SYSTEM_CENTER_*` excluded) that isn't in that list or `lib/notifications-reviewed.list` is an `info` line, so a newly appeared app gets flagged. A missing store or a plist that doesn't parse is a warning; the check does not crash.

On macOS 27 the store is `~/Library/Group Containers/group.com.apple.usernoted/Library/Preferences/group.com.apple.usernoted.plist` (binary plist, key `apps`). `~/Library/Preferences/com.apple.ncprefs.plist` is not used. `lib/notification-prefs.py` reads it with `python3` `plistlib` and never writes it. `--fix` does not change it.

Allow Notifications is `flags` bit 25 (`1 << 25`), set = on. The constant is `ALLOW_NOTIFICATIONS_BIT` in `lib/notification-prefs.py`. That is the bit Hush uses for this same plist on macOS 26, and the bit ncmanager used for the older ncprefs store. On this Mac every Off-list app has the bit clear, and Chrome (`com.google.Chrome`, flags `41951246`) is the sample that has it set.

To recalibrate after a macOS update, see [Troubleshooting](troubleshooting.md#recalibrating-notification-bits).

**Hammerspoon's notification style** is checked in that same read (manual step `mode-hammerspoon-alerts`). Alerts is `flags` bit 4 set and bit 3 clear. Hush names those `alertPersistent` (`1 << 4`) and `alertTemporary` (`1 << 3`) on this usernoted plist; bit 3 alone is Banners, and both clear or both set is None (Hush treats both-set as Off). ncmanager's older ncprefs store uses the same two bits (`style_alerts`, `style_banners`). The constant is `ALERT_STYLE_BIT` (banner bit: `BANNER_STYLE_BIT`). On this Mac Hammerspoon's flags are `8396822`, which is Alerts. Anything else is a warning (**Needs Paul**). `--fix` does not write the store.

To recalibrate the style bits, see [Troubleshooting](troubleshooting.md#recalibrating-notification-bits).

Notifications Off when mirroring stays by hand.

## Finder

Per-window View Options and chrome (kept manual so folder views stay intentional; the default icon view 72/13 is pinned by `macos.sh` and checked by `macconfig-check.sh`):

1. Open any Finder window → **View → Show View Options** (`Command + J`)
2. Set **Icon size** to **72×72**
3. Set **Text size** to **13**
4. Optionally tick **Use as Defaults** if you want new icon-view windows to inherit these sizes
5. **Show Status Bar** — managed by `macos.sh` / `macconfig-check.sh` (`com.apple.finder ShowStatusBar`); UI path: **View → Show Status Bar**
6. **Show all filename extensions** — managed by `macos.sh` / `macconfig-check.sh` (`NSGlobalDomain AppleShowAllExtensions`); UI path: **Finder → Settings… → Advanced**

These next ones are in `lib/macos-defaults.list`. `macos.sh` applies them, `macconfig-check.sh` checks them, and `macconfig --fix` repairs them through the `defaults` row in `lib/autofix.list`. A change restarts Finder. Screenshot keys restart SystemUIServer.

7. **Remove items from the Trash after 30 days** — `com.apple.finder FXRemoveOldTrashItems` = true. UI: **Finder → Settings… → Advanced**
8. **When performing a search** — search the current folder (`FXDefaultSearchScope` = `SCcf`). UI: **Finder → Settings… → Advanced**
9. **Keep folders on top** — `com.apple.finder _FXSortFoldersFirst` = true. UI: **Finder → Settings… → Advanced**
10. **No .DS_Store on network volumes** — `com.apple.desktopservices DSDontWriteNetworkStores` = true. The domain may not exist until the first write; writing creates it.
11. **Screenshots** — `com.apple.screencapture location` = `~/Pictures/Screenshots` (`@HOME@` in the list, expanded to `$HOME` at runtime) and `show-thumbnail` = true, so the floating thumbnail stays. `install.sh` creates the folder. `macos.sh`, including `macconfig --fix`, runs `mkdir -p` on that path before setting the location. A missing folder is drift. Files already in `~/Pictures` are not moved.

Re-check after a major macOS upgrade; View Options can reset per folder.

## Logi Options+

MX Master 3S settings, all checked read-only by the **Logi Options+** section of `macconfig-check.sh` (expected values: `lib/logi-expected.list`):

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

## Gemini

Default Gemini shortcuts (`Option + Space` / `Option + Shift + Space`) clash with ChatGPT. Set via Gemini Settings → Shortcuts:

| Action | Shortcut |
|------|------|
| Mini chat | `Control + Option + G` |
| Full chat | `Control + Option + Shift + G` |

## Raycast

Move Raycast off `Option + Space` (clashes with ChatGPT): Settings → General → Raycast Hotkey → `Shift + Control + Command + R`.

Finder comes to the front with `Shift + Control + Command + F` in Hammerspoon ([Shortcuts](../SHORTCUTS.md#hammerspoon)). If the Raycast backup being imported still has a Finder hotkey on Shift+Control+Command+F, unbind it in Raycast so it doesn't clash with Hammerspoon.

To enable Clipboard History:
1. Open Raycast and run the **Clipboard History** command once
2. Grant Accessibility permission if prompted (System Settings → Privacy & Security → Device Control and Data Access (Accessibility before macOS 27) → enable Raycast)
3. Bind a hotkey via Raycast Settings → Extensions → search "clipboard", then in the **Clipboard History** row of type **Command** (not the parent "Extension" row), click **Record Hotkey** and press `Control + Command + V`.
   - Avoid `Command + Shift + V` (paste without formatting) and `Command + Option + V` (Finder paste-as-move).
4. Set **Keep History For** to 1 Day
5. Add password apps to **Disabled Applications** so their copies are never recorded: 1Password, 1Password for Safari

## Running one part of the check

`macconfig`, `check.sh`, and `macconfig-check.sh` are the same check. Any arguments you pass to `macconfig` or `check.sh` are handed straight through, including `--only`.

```bash
macconfig --only dock
./macconfig-check.sh --only dock,power
./check.sh --only security --no-color
```

`--only` runs just those areas, in the usual order, not the order you type them. `--only hostname,shell` still prints Login shell before Hostname. `macconfig --help` lists the area names. `finder` covers both Finder sections (icon view, then sidebar Recents). The summary, the exit status, `--fix`, `--no-color`, and `--health-json` work the same way on a subset: exit status is still 1 when that subset has drift, and `--fix` only repairs SAFE items from the areas you asked for.

## Checks that only warn

These read the Mac. They never change it. They do not use sudo, they do not write the notification store, and `macconfig --fix` does not "fix" them. If a command is slow, it is cut off.

**FileVault.** `fdesetup status` should say FileVault is On. If it doesn't, or if the command fails, you get a warning under Security hygiene.

**Firewall stealth mode.** `socketfilterfw --getstealthmode` should say stealth mode is on. The check never turns it on.

**Automatic security updates.** The employer (MDM) manages these. The check reads `CriticalUpdateInstall`, `ConfigDataInstall`, and `AutomaticallyInstallMacOSUpdates` from the Software Update preferences and prints the values it saw, as an info line. An off or missing value is not a warning, and nothing tries to turn the toggles on.

**A macOS update that has been waiting.** The check does not phone Apple. It reads `RecommendedUpdates` and `LastSuccessfulDate` from the local Software Update preferences (the system file if it is readable, otherwise yours). No recommended update is fine. A recommended update whose last successful check is more than 7 days ago is a warning. A newer pending update is an info line, not a warning.

**Free disk space.** Mac health warns when the Data volume is under 15% free, and also when it is under 50 GB free. One warning covers either case.

**SSH and commit signing.** The check does not warn when no SSH key is loaded in the agent, and it does not try to load one. `~/.ssh` should be mode 700, and private keys mode 600. Commit signing is not used, so an unset `commit.gpgsign` is not reported. If it is turned on and `gpg.format` is `ssh`, a dry `ssh-keygen -Y sign` must succeed. Nothing here writes a commit or a key.

**Broken dotfiles links.** Symlinks under `~/.config`, `~/Library/LaunchAgents`, and the dotfiles in your home directory are checked. A link that points into the dotfiles repo (or `~/.dotfiles-mac`) and whose target is missing is a warning. The check does not relink it. Ordinary managed links are still the Symlinks section, which `--fix` can repair.

**Default browser.** Besides the `duti` URL-handler check, the LaunchServices handler list is read for `http` and `https`. Both should be Chrome (`com.google.chrome`). The check does not change the default browser.

**Hammerspoon's config.** The app should be running. If the `hs` command can talk to it, the repo `hammerspoon/init.lua` is compiled in that process (`loadfile` only, so the config is not run a second time). If `hs` isn't available, the process check stands and `luac` or `lua` syntax-checks the same file. A compile error is a warning. `--fix` can still start Hammerspoon when it isn't running; it does not rewrite the config.

**com.pdone LaunchAgents.** Every `com.pdone.*` file in `~/Library/LaunchAgents` is compared with the repo template after `@HOME@` is replaced with your home directory. An installed plist with no template is stale or unknown and is a warning. The two pin agents are still reported in the Dictation and Quick Note sections, and `--fix` can still rewrite those. This extra sweep only reports; it does not write a plist.
