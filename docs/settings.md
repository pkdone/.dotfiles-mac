# Settings

See [README.md](../README.md).

This is what each managed setting does, and why. Applying them is the [setup walkthrough](setup.md). The by-hand list is [Manual steps](manual-steps.md). After a software update, hotkey pins, and AC sleep are in [Troubleshooting](troubleshooting.md).

## Quiet Apple apps (containment)

System apps (Music, Photos, News, …) can't be deleted (SIP). This repo contains them where scripting is reliable. The keys are under [macOS defaults](#macos-defaults) unless a line below names the file.

- **URL handlers** → Chrome (`handlers.sh` / `lib/url-handlers.list`). See [Setup](setup.md#url-handlers-chrome-not-apple-apps).
- **GarageBand / iMovie / Pages** removed (`prune-apps.sh`)
- **Photos auto-open on device connect** Off (`com.apple.ImageCapture disableHotPlug` in `lib/macos-defaults.list`)
- **Menu bar, Control Centre, and Allow in the Menu Bar** — [macOS defaults](#macos-defaults)
- **Dock minimize, bounce, and the desktop-switch delay** — [macOS defaults](#macos-defaults)
- **Finder** sidebar, icon view, tidy, extensions, and CotEditor — [Finder](#finder)
- **Window tiling, desktop widgets, and Stage Manager** — [macOS defaults](#macos-defaults). Shortcuts are in [SHORTCUTS.md](../SHORTCUTS.md)
- **Login Items:** Tailscale must be in Open at Login. It has no launch-at-login option of its own. When `/Applications/Tailscale.app` is installed and missing from that list, the check says: System Settings → General → Login Items & Extensions → under Open at Login click + → Applications → Tailscale → Open. The list is only read. `--fix` does not add it. An uninstalled Tailscale is left alone. Tailscale's team and bundle ids are on `lib/login-items-allow.list`, so that entry is expected. WhatsApp Web (the Safari web app at `~/Applications/WhatsApp Web.app`) is also expected under Open at Login. Its bundle id is different on each Mac, so the list names it by that path, and no other Safari web app is allowed by it. Docker Desktop's helper (DockerHelper, `com.docker.helper`, Docker Inc team `9BNSXJN65R`) is expected too, because the Brewfile installs Docker Desktop

Universal Links like `https://music.apple.com` may still open Apple apps — use Chrome when it matters.

## Keyboard / Dictation / Fn

**Goal:** hold-Fn/Globe must never start the mic (Dictation / Apple Intelligence).

**Scripted + checked** (`macos.sh` / `macconfig-check.sh`):
- Fn/Globe → **Do Nothing** (`AppleFnUsageType` = `0`)
- Dictation **Off**
- Symbolic hotkey 164 ("Start Dictation") pinned to **Right Command twice** — a *dummy* unused combo so Press 🎙️ / Fn never owns it. Do **not** use Right Command twice yourself; it would fire dictation if Dictation were on.
- Symbolic hotkey 190 ("Quick Note") disabled so Globe/Fn+Q does not open Notes (`enabled=0`, `type=standard`, unbound parameters).
- Symbolic hotkey 260 ("Game Overlay") disabled so Command+Escape does not open the Game Overlay (`enabled=0` or `false`, `type=standard`, parameters `65535, 53, 1048576`). That is the shape System Settings writes when Mission Control → Game Overlay is unticked. A software update turns it back on, so a LaunchAgent re-pins it at login and when `com.apple.symbolichotkeys` changes. `macos.sh` and the agent write only when the value differs.
- Symbolic hotkey 64 ("Show Spotlight search") stays **Command+Space** (`enabled=1`, `type=standard`, parameters `32, 49, 1048576`). Raycast's Replace Spotlight button turns it off. `macos.sh` writes it only when the value differs. `macconfig --fix` writes the same value and runs `activateSettings -u`. There is no LaunchAgent for it. Spotlight's desired value is the factory Command+Space binding, so it does not get the login agent Game Overlay and Quick Note use.
- Services in `lib/services-off.list` stay off (System Settings → Keyboard → Keyboard Shortcuts → Services). Each key in `pbs` `NSServicesStatus` has `enabled_context_menu` and `enabled_services_menu` at 0, and `presentation_modes` ContextMenu and ServicesMenu at 0. `defaults read` may print `false` for any of those. On macOS Tahoe it quotes some names (`"enabled_context_menu" = 0`) and leaves `ContextMenu` and `ServicesMenu` bare. A quoted name and a bare name are the same field. `macos.sh` merges the listed keys with `-dict-add` and does not change any other service. It writes only when a listed key differs, then runs `/System/Library/CoreServices/pbs -flush`. There is no LaunchAgent. Stickies only had the Services menu saved. The pin writes both menus off, and the same presentation modes Safari already has. New CotEditor Window Containing Selection, New TextEdit Window Containing Selection, and Summarise are unticked and have no saved `pbs` entry, so they are off by default and are not written.

What a macOS Software Update does to these hotkeys, and how to reload a LaunchAgent on this Mac, is in [Troubleshooting](troubleshooting.md#after-a-macos-software-update). Command+Space is in [Troubleshooting](troubleshooting.md#spotlight-commandspace). Services shortcuts are in [Troubleshooting](troubleshooting.md#services-shortcuts).

**Karabiner** (Brewfile cask `karabiner-elements`; `karabiner/` → `~/.config/karabiner/` as a **directory** symlink — Karabiner won't watch a file symlink):
- Fn/Globe only sets internal variable `pdone_fn` (never sent to macOS)
- While held: Fn+F → ⌃⌘F (fullscreen); Fn+F11 → Show Desktop; Fn+Delete → forward-delete outside Finder, and in Finder moves the selected item to the Bin; Fn+arrows → Home/End/PgUp/PgDn
- Dictation/microphone consumer keys swallowed; Forward Delete on an external keyboard in Finder also moves the selected item to the Bin
- Top-row brightness/volume still work without Fn
- Menu bar icon hidden: `global.show_in_menu_bar` and `show_profile_name_in_menu_bar` are both `false` in `karabiner/karabiner.json` (the directory symlink's `~/.config/karabiner/karabiner.json`). `macconfig-check.sh` reads that file with python3 and drifts if either is not false. Restore is git (`karabiner-rules` in `lib/autofix.list`); `--fix` does not rewrite it
- `macconfig-check.sh` drifts if the dir symlink, Fn-kill rule, Finder Trash rule, or menu bar icon setting is missing

**Manual once (TCC / DriverKit):** Open Karabiner-Elements first so it asks for its driver. Then System Settings → General → Login Items & Extensions: scroll to Extensions, choose By Category, click ⓘ next to Driver Extensions, and turn on .Karabiner-VirtualHIDDevice-Manager. For Accessibility, open the app first; if it is not listed, click + and add it from Applications. See [Manual steps](manual-steps.md) (`karabiner-driver`, `karabiner-ax`; `macconfig-check.sh` verifies the driver and the Core-Service grant). Allow in the Background is checked too: Karabiner-Core-Service and Karabiner-VirtualHIDDevice-Daemon must be enabled and allowed. Karabiner-Elements Privileged Daemons v2 may stay disabled. The check reads the same background-item records `sfltool dumpbtm` prints, and it does not change them. If those records cannot be read, it tries `sfltool dumpbtm` for a few seconds and, if that does not finish, leaves the step as info. Karabiner 16+ does not need Input Monitoring. If DriverKit never enables, work MDM/EDR may be blocking Team ID `G43BCU2T37`.

## App settings as code (Ghostty, Raycast)

**Ghostty: fully in the repo.** `ghostty/config` is symlinked to `~/.config/ghostty/config` (`lib/links.list`). `macconfig-check.sh` (the **Ghostty config** section) checks four things:

- the link
- that the repo file is valid (`ghostty +validate-config`)
- that no other file Ghostty loads overrides it (`~/Library/Application Support/com.mitchellh.ghostty/config` or `config.ghostty`, and `~/.config/ghostty/config.ghostty`)
- that Ghostty's effective config (`ghostty +show-config`) is exactly what the repo file alone produces

A broken link is restored by `macconfig-check.sh --fix`. An override file is reported but never deleted automatically.

**Raycast: set by hand.** Raycast keeps almost everything in an encrypted database (`~/Library/Application Support/com.raycast.macos/raycast-enc.sqlite`). When `com.raycast.macos raycastGlobalHotkey` is present it should be `Shift-Control-Command-15` (key code 15 is R), and a different value is a warning. Current Raycast often does not store that key at all, even after the hotkey is set; a missing key is check by hand, not a warning. Clipboard History stays by hand. Shift+Control+Command+F brings Finder to the front from Hammerspoon (`hammerspoon/finder_hotkey.lua`).

Spotlight's Command+Space is macOS symbolic hotkey 64, not a Raycast setting. The Spotlight shortcut check keeps it enabled. `macconfig --fix` writes it back. Don't click Raycast's **Replace Spotlight** button: that turns hotkey 64 off. The click path is in [Raycast](#raycast) below.

**Logi Options+: checked, never written.** The values are in [Logi Options+](#logi-options). Logi Options+ keeps them as JSON inside a private SQLite database (`~/Library/Application Support/LogiOptionsPlus/settings.db`; the agent caches it and syncs it to the mouse). `lib/logi-settings.py` copies the database (plus its `-wal` / `-shm`) to a temp dir, reads the copy read-only, deletes it, and compares the MX Master 3S (model `2b034`, not serial number) with `lib/logi-expected.list`. The **Logi Options+** section of `macconfig-check.sh` reports drift as **Needs Paul** (`logi-settings` in `lib/autofix.list`; `--fix` never touches it), and a missing app, missing database or unreadable format as a warning (`logi-unreadable`), never a failure of the run. Restore is by hand in the app or from Logi's cloud backup (manual step `logi-cloud-backup`). Cloud backup itself stays **by hand**: the **Automatically backup all devices** toggle and the last-backup time aren't in any readable local file (the per-device `settings_backup_state_v2` flags in `settings.db` stay false with backup on), so there's nothing reliable to check. Manual step `logi-smooth-scrolling` uses the same helper (`logi:<id>` check). The macOS natural-scrolling switch is global and also flips the trackpad, so the wheel direction stays in Logi Options+.

## macOS defaults

> _Run by `bootstrap.sh`; the commands below run only this step._

A curated set of macOS `defaults` is applied by `macos.sh` (plus Dictation hotkey 164, Quick Note hotkey 190, Game Overlay hotkey 260, Spotlight hotkey 64, the Services shortcuts in `lib/services-off.list`, CotEditor theme/font, Finder sidebar Recents, Finder Favorites, the Show Finder shortcut, power settings, the built-in display's More Space mode, and the ARZOPA portable monitor when it is plugged in):

```bash
~/.dotfiles-mac/macos.sh --dry-run   # preview every decision, write nothing
~/.dotfiles-mac/macos.sh             # apply
```

A full `macos.sh` reads each `lib/macos-defaults.list` row, then writes the desired value, including when it already matches. A boolean and an integer 0 or 1 are the same value. A difference is written with the type already stored (`-bool` when the key is a boolean). Any other unexpected type is skipped, with a warning. Missing keys are set. `macos.sh --only` (what `macconfig --fix` calls) leaves a match alone. Dictation hotkey 164 and Quick Note hotkey 190 follow that same split: a full run re-asserts, and `--only` leaves a match. Game Overlay hotkey 260, Spotlight hotkey 64, and the Services list are written only when the value differs, including on a full run. Before the first actual change it backs up each affected domain to `backups/defaults-<timestamp>/`. UI restarts (Dock, Finder, menu bar) happen at the end only when something actually changed, after you confirm.

Dark mode is `NSGlobalDomain` `AppleInterfaceStyle` = `Dark`. A full run writes that row the same way as the other list rows. `macos.sh` also tells System Events to turn dark mode on immediately when it is not already on, so a logout is not required. That live call is the part that skips when dark mode is already on. If System Events refuses (often a missing Automation permission), that is a warning and the default is still written. `macconfig --fix` uses the same path.

Theme colour is Graphite: System Settings → Appearance → Theme → Colour: Graphite. That is `NSGlobalDomain` `AppleAccentColor` = `-1` (an integer). `AppleAccentColor` goes through the same write as the other list rows: a full run re-asserts `-int -1`, and `--only` leaves a match. `macconfig-check.sh` reads that row and reports drift when the accent is missing or is not `-1`. `AppleHighlightColor` is left unset, so the highlight follows the accent. Nothing writes it. Graphite may need a logout, or each app opened again, before it shows everywhere. The needs-logout list at the end of setup includes this accent only when the value changed.

Power is the one `macos.sh` step that uses sudo. It runs only the `pmset` commands that are still wrong: AC sleep 0, AC display sleep 10 minutes, battery display sleep 2 minutes, and AC wake for network access. A desktop Mac has no AC Power section, so that case is a warning. `--fix` does not run sudo. See [Troubleshooting](troubleshooting.md#ac-idle-sleep).

Trackpad rows in that list are tap to click (built-in trackpad, Bluetooth trackpad, and `com.apple.mouse.tapBehavior`), click pressure Light, secondary click in the bottom right corner, three-finger drag Off, tracking speed `0.6875`, Force Click and haptic feedback On (`ActuateDetents=1`, `ForceSuppressed=0`), natural scrolling On, swipe-between-pages Off, three-finger tap Off, and the 3/4/5-finger swipe and pinch gestures. On a fresh Mac the 0/1 keys may already be booleans. That matches integer 0 or 1, so it is not a type mismatch, and a wrong value is written with `-bool` when that is the type already stored. The gesture keys are written for both the built-in trackpad and the Bluetooth trackpad. Secondary click stays the bottom-right corner (`TrackpadCornerSecondaryClick` = 2) and a right-side click stays off (`TrackpadRightClick` = 0). Each one sets `restart` to `logout`. When a value changes, `macos.sh` runs `activateSettings -u` when that tool is present, so the trackpad follows the new value without a logout. If it is missing or fails, the change is listed as needing a logout, and `bootstrap.sh` prints that list at the end of setup. `macconfig-check.sh` reads the same list, and `macconfig --fix` repairs drift through the `defaults` row in `lib/autofix.list` and uses the same reload. Look up & data detectors is checked (`com.apple.trackpad.forceClick` = 0) and not written. Use trackpad for dragging stays a check (`Dragging=1`, `DragLock=0`: On, without drag lock) because that Accessibility setting does not reliably follow `defaults write`. Mouse tracking speed `1.5` (7th notch from Slow) and scrolling speed `0.5` (5th notch from Slow) stay a check only, because writing them does not stick. The double-click threshold key is unset on this Mac, so it cannot be checked. Leave Double-Click Speed, Click Right Side, and Natural scrolling as they are. Logi Options+ sets the wheel direction.

Finder and Trash tidy rows in that list remove Trash items after 30 days (`com.apple.finder FXRemoveOldTrashItems`), search the current folder (`FXDefaultSearchScope` = `SCcf`), keep folders on top (`_FXSortFoldersFirst`), and skip `.DS_Store` on network volumes (`com.apple.desktopservices DSDontWriteNetworkStores`). That domain may not exist until the first write; writing creates it. Those four set `restart` to `Finder`. The Tags group in the sidebar stays closed (`SidebarTagsSctionDisclosedState` = false; Apple's key is spelled that way). Screenshots and screen recordings save to `~/Pictures/Screenshots` (`com.apple.screencapture location`, stored as `@HOME@/Pictures/Screenshots` so apply and check expand `$HOME`), keep the floating thumbnail (`show-thumbnail` = true), use window capture (`style` = `window`), and leave video capture on (`video` = 1). macOS may store video capture as an integer or a boolean. Either one counts as on, the same way as every other 0/1 setting, so that difference is not drift, and `macconfig --fix` leaves an on value alone. `location` is the save folder for both screenshots and recordings. Those keys set `restart` to `SystemUIServer`. `install.sh` creates `~/Pictures/Screenshots` with `mkdir -p`. `macos.sh` does the same before it writes the location, including when `macconfig --fix` repairs that key. Existing screenshots are left where they are.

Finder sidebar Favorites are `lib/sidebar-favorites.list` (Applications, Desktop, Developer, Documents, Downloads, Movies, Music, Pictures). `macos.sh` and `macconfig-check.sh` read `~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.FavoriteItems.sfl4` (or `.sfl3`, or `.sfl2`, whichever file this Mac has) and compare the file favorites with that list. A match is left alone. A difference is a warning. A missing FavoriteItems file is not a warning: Finder may not create it until the sidebar is edited, so that is an info line you check by hand. It is not part of the ok total. Nothing writes the sidebar file: Homebrew has no `mysides` formula or cask, and editing that file directly is not reliable, so `macconfig --fix` does not change Favorites. The Tags group stays collapsed (`SidebarTagsSctionDisclosedState`; Apple spells it that way). Recents stays hidden. Shared stays hidden, AirDrop and iCloud Drive stay hidden, and the Locations rows (your home folder, Macintosh HD, Network, Trash) are checked when the sidebar files name them. A row the files do not name stays by hand. No tags shown in the sidebar is manual step `finder-sidebar-tags`: Finder → Settings → Tags → untick every box under Show these tags in the sidebar. `FavoriteTagNames` is not that list. On this Mac every box is unticked and the sidebar has no Tags section, but `defaults read com.apple.finder FavoriteTagNames` still returns `("", Red, Orange, Yellow, Green, Blue, Purple, Grey)`. Tags sync through iCloud (`TagsCloudSerialNumber`). The check does not read that key and does not warn. `SidebarShowingiCloudDesktop` is still not checked. `macconfig --fix` does not change the sidebar.

Show Finder is the menu shortcut Cmd-Ctrl-Shift-F (`com.apple.finder` `NSUserKeyEquivalents`, added with `-dict-add` so other menu shortcuts stay). Hammerspoon uses the same keys to bring Finder to the front from any app (`hammerspoon/finder_hotkey.lua`). Double-clicking a window's title bar fills the window (`AppleActionOnDoubleClick` = `Fill`). If the older minimize-on-double-click key is set, `macos.sh` deletes it.

The built-in display's More Space mode is set by `macos.sh` with `displayplacer` (Homebrew formula `displayplacer`) when that mode is listed for the panel in `lib/display-resolution.list` (14" panel `3024x1964`: `1800 x 1169`, 16" panel `3456x2234`: `2056 x 1329`). The check warns when `_spdisplays_resolution` does not start with that value. The current refresh rate is kept when a scaled mode at that rate exists. Other displays are left on their current mode, except the ARZOPA 16.1" portable monitor: when it is plugged in, the same command sets it to 1920x1080 with scaling off, to the left of the laptop (origin -1920,0; the laptop stays at 0,0), at 180Hz, or at the highest rate the connection offers when 180Hz is not (144Hz through the StarTech Thunderbolt 5 dock). If that rate does not take, the next rate down is tried. The monitor is matched by name (ARZOPA) or serial `s74646035`. displayplacer's type, "16 inch external screen", counts only when that block does not already name a different product or serial. The persistent screen id is not used, because macOS changes it when the cable moves to another port. A missing `displayplacer` or a missing mode is a warning and stays the manual step (System Settings → Displays). `macconfig --fix` uses the same path. An unlisted panel size, no built-in panel (such as a clamshell Mac), or an unplugged ARZOPA is an info line. It is left alone, and it is not part of the ok total or the by-hand count. The walk-through does not open an unplugged ARZOPA.

The desktop picture is Tahoe Night (Landscape). `macconfig-check.sh` looks for asset `CF6347E2-4F81-4410-8892-4830991B6C5A` in the wallpaper store and warns if it is absent. That picture is a wallpaper-catalog asset, not a file under `/System/Library/Desktop Pictures`, so System Events cannot select it. The wallpaper store is not written. `--fix` does not change the picture. Set it by hand in System Settings → Wallpaper.

Automatically adjust brightness stays by hand (System Settings → Displays). It needs an admin password, and the saved value is a root-owned file. `bootstrap.sh` names this step when it prints the manual steps, and the walk-through opens Displays. True Tone and Slightly dim the display on battery are left alone.

The account picture is the Dog. `macconfig-check.sh` hashes the JPEGPhoto on the user account (the same bytes as `dscl . -read /Users/$USER JPEGPhoto | tail -n +2 | xxd -r -p`) and compares it with `lib/user-picture.sha256`. A different picture is a warning. `--fix` does not change it.

Window tiling rows in that list turn on drag-to-edge tiling (`com.apple.WindowManager EnableTilingByEdgeDrag` = true) and turn tiled-window margins off (`EnableTiledWindowMargins` = false). On this Mac the edge-drag key is unset, which is the system default On, and margins read as `0` (boolean false). Both rows leave `restart` empty. WindowManager applies the domain live: writing the margins key moves windows that are already tiled, and the edge-drag key is read on the next drag, so `macos.sh` restarts no process for them. `macconfig-check.sh` reads the same list, and `macconfig --fix` repairs drift through the `defaults` row in `lib/autofix.list`. HideDesktop, drag-to-menu-bar, the Option-drag toggle, and Click wallpaper to reveal desktop (`EnableStandardClickToShowDesktop`) stay out of the list. Moving the window on to the next desktop is separate: `com.apple.dock workspaces-edge-delay` waits 5 seconds at the edge before that happens, and the snap itself is unchanged. Desktop pins in `lib/desktop-bindings.list` stay as they are.

Stage Manager and desktop widgets are three more `com.apple.WindowManager` rows. `StandardHideWidgets` = true and `StageManagerHideWidgets` = true hide widgets (System Settings → Desktop & Dock → Widgets → Show Widgets: On Desktop off, and In Stage Manager off). `GloballyEnabled` = false turns Stage Manager off. Those rows leave `restart` empty too. WindowManager applies the domain live, so `macos.sh` does not `killall Dock` (that reloads Spaces) or WindowManager. `macconfig --fix` repairs them through the same `defaults` row in `lib/autofix.list`. Hiding a widget does not delete it. On this Mac, Calendar, Weather and Photos stayed on the desktop with `StandardHideWidgets` true, and they show again when the desktop is revealed. Placed widgets are the `widgets` → `instances` array in `~/Library/Containers/com.apple.notificationcenterui/Data/Library/Preferences/com.apple.notificationcenterui.plist` (one data blob per widget), next to `DesktopWidgetPlacementStorage`. The **Desktop widgets** section of `macconfig-check.sh` reads that array. A missing or empty `instances` array is ok. One or more instances is a warning (`N widgets on the desktop`, plus a kind bundle id when the nested plist has a readable extension or kind). A plist that cannot be read is check by hand. Removing one is manual step `remove-widgets`: Control-click (or right-click) each widget → Remove Widget. `macconfig --fix` does not write that plist and does not kill NotificationCenter or chronod.

Menu bar rows in that list hide Spotlight, Focus, Now Playing and Voice Control (`@host/com.apple.controlcenter` = `8`, Don't Show), keep Bluetooth in the menu bar (`Bluetooth` = `2`, Show in Menu Bar), and show the battery percentage (`BatteryShowPercentage` = true; `defaults read` prints `1` because the type is boolean). Each of those sets `restart` to `ControlCenter`. `macos.sh` runs `killall ControlCenter` only when a value changed. `macconfig --fix` repairs drift through the `defaults` row in `lib/autofix.list`. The intended menu bar is the clock, the mode icon, battery percentage, Wi-Fi, Bluetooth and Control Centre, plus Tailscale, Hammerspoon and Fleet Desktop. Wi-Fi is already shown and is not pinned here. Karabiner-Elements stays out of the menu bar via `karabiner.json`.

Allow in the Menu Bar (manual step `menubar-third-party-hide`) turns off 1Password, Cursor, Cursor Nightly, Docker, Granola, Microsoft Teams, Slack, Zoom, Raycast and Logi Options+. Tailscale, Hammerspoon, Fleet Desktop and the rest stay as they are. On macOS 26 (Tahoe) the toggles are `trackedApplications` in `~/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist`. That value is a data blob, and the blob is a binary plist: an array alternating `{'bundle': {'_0': <bundle id>}}` and `{'location': {'bundle': {'_0': <id>}}, 'menuItemLocations': [...], 'isAllowed': bool}`. `lib/menubar-allow.py` reads it and compares the apps in `lib/menubar-allow.list`. An app that is allowed and should be off is drift. An app that is not installed, or not in `trackedApplications` yet, is an info line. A missing or unreadable plist is a warning. Docker's menu-item bundle can be `com.electron.dockerdesktop`; the toggle is `com.docker.docker`. Writing this blob is undocumented and Control Center may overwrite it, so `macconfig --fix` does not change it (`menubar-allow` in `lib/autofix.list` is Needs Paul).

Control Centre tiles are a different list (manual step `control-centre-controls`). Keep Screen Mirroring, Wi-Fi, Bluetooth, Now Playing, Display, Sound and Keyboard Brightness. Remove AirDrop, Stage Manager, Dark Mode, Screenshot and Focus. Keyboard Brightness stays in Control Centre and is not a menu-bar pin. The only readable layout file is `~/Library/Preferences/ByHost/com.apple.controlcenter.bentoboxes.<host UUID>.plist`. It keeps a history of module instances in an undocumented nested binary format, and it was not updated when the tiles were removed. On 25 Oct 2026 it still listed AirDrop and FocusModes hours after they were gone, so it can't tell whether a tile is showing. `trackedApplications` is the third-party Allow in the Menu Bar list, not built-in modules. Bluetooth is `2` (Show in Menu Bar) and Now Playing is `8` (Don't Show), and both stay in Control Centre, so the integer does not say whether the tile is showing. A published mapping (2 hidden everywhere, 8 Control Centre only, 18 both) disagrees with this Mac. Nothing writes that file. The step stays by hand.

Dock behavior rows in that list minimize windows into the application icon (`com.apple.dock minimize-to-application` = true) and turn off the bounce when an app opens (`no-bouncing` = true; System Settings → Desktop & Dock → Animate opening applications Off). Both set `restart` to `Dock`, the same as icon size, recent apps, Hot Corners, and the 5 second delay before a window moves to the next desktop (`workspaces-edge-delay`). Icon size stays exactly `28`. A change restarts Dock. `macconfig --fix` repairs drift through the `defaults` row in `lib/autofix.list`. App order and the Desktop pins are in [Setup](setup.md#dock).

Run `macos.sh --list` to see the exact set of settings it manages (printed as a Markdown table).

## Notifications

Per-app **Allow Notifications** is checked by the **Notifications** section of `macconfig-check.sh`. The apps that must be off are only the seven in `lib/notifications-off.list`: Calendar, FaceTime, Game Center, Home, Tips, Wallet, and Messages. An app in that list whose Allow Notifications is on is a warning (**Needs Paul**). An app that is not in the notification store has never posted a notification, so it cannot be on: that is an info line (`not registered for notifications yet, nothing to turn off`), not a warning. Messages shows **Critical** in System Settings when normal notifications are off and Critical Alerts are still allowed. Bit 25 clear is not a warning, and it is not reported as off. A clear bit only says the bit is clear. Hammerspoon's Alerts style is the same read: until Hammerspoon has posted a notification, the style can't be checked, and that is an info line. Hammerspoon being allowed to notify is not a warning. A third-party app (`com.apple.*` and `_SYSTEM_CENTER_*` excluded) that isn't in that list or `lib/notifications-reviewed.list` is an `info` line, so a newly appeared app gets flagged. Cursor, Cursor Nightly, Ghostty, both Google Chrome entries, Grok Bot, Microsoft Teams, Slack, Spotify, Tailscale, Zoom, Santa, and SentinelAgent are reviewed, so on is not a warning. Find My, Finder, Kerberos, and WhatsApp Web are `com.apple.*` ids, so they are ignored. Do not add Santa, SentinelAgent, or Kerberos to the off list. A missing store or a plist that doesn't parse is a warning; the check does not crash. When one of the seven apps is still on, the manual-steps reason line is `NOTSET:` and the check's detail. Leave Santa, SentinelAgent, and Kerberos as they are. The check never asks you to turn those off.

On macOS 27 the store is `~/Library/Group Containers/group.com.apple.usernoted/Library/Preferences/group.com.apple.usernoted.plist` (binary plist, key `apps`). `~/Library/Preferences/com.apple.ncprefs.plist` is not used. `lib/notification-prefs.py` reads it with `python3` `plistlib` and never writes it. `--fix` does not change it.

Allow Notifications is read from `flags` bit 25 (`1 << 25`). The constant is `ALLOW_NOTIFICATIONS_BIT` in `lib/notification-prefs.py`. That is the bit Hush uses for this same plist on macOS 26, and the bit ncmanager used for the older ncprefs store. A clear bit is not reported as off.

To recalibrate after a macOS update, see [Troubleshooting](troubleshooting.md#recalibrating-notification-bits).

**Hammerspoon's notification style** is checked in that same read (manual step `mode-hammerspoon-alerts`). Alerts is `flags` bit 4 set and bit 3 clear. Hush names those `alertPersistent` (`1 << 4`) and `alertTemporary` (`1 << 3`) on this usernoted plist; bit 3 alone is Banners, and both clear or both set is None (Hush treats both-set as Off). ncmanager's older ncprefs store uses the same two bits (`style_alerts`, `style_banners`). The constant is `ALERT_STYLE_BIT` (banner bit: `BANNER_STYLE_BIT`). Anything else is a warning (**Needs Paul**). `--fix` does not write the store.

To recalibrate the style bits, see [Troubleshooting](troubleshooting.md#recalibrating-notification-bits).

Notification Centre stays by hand. The four controls at the top of System Settings → Notifications are Show previews **When Unlocked**, **when display is sleeping** off, **when screen is locked** on, and **Notifications Off** when mirroring or sharing the display (manual steps `notifications-previews`, `notifications-display-sleep`, `notifications-lock-screen`, `notifications-mirroring`). They are not the per-app flags. An app's own preview (`content_visibility`: Default, Never, When Unlocked, Always) is a different control. `~/Library/Preferences/com.apple.ncprefs.plist` is not the store on macOS 27. No key in the usernoted plist has been shown to match those four controls, so the check does not read them and does not warn when a guessed key is missing. Nothing writes them. `manualsteps` and `macconfig` label each one `MANUAL: Can't check this automatically. If it's already set, press s.` When one of the seven apps is still on, that reason line is `NOTSET:` and the check's detail.

## Finder

Per-window View Options and chrome. The default icon view is pinned by `macos.sh` and checked by `macconfig-check.sh`: icon size 72, text size 13, and Sort By Name (`arrangeBy` = `name`) on `StandardViewSettings` and `FK_StandardViewSettings`. The Desktop is sorted by name too (`DesktopViewSettings` → `IconViewSettings` → `arrangeBy` = `name`). Only the Desktop's sort is written: its icon size and text size stay as they are. A full run re-asserts the icon view when it already matches. `macos.sh --only` leaves a match alone. `macconfig --fix` repairs all three (`finder-icon-view` in `lib/autofix.list`). Finder is restarted with `killall Finder`, the same restart the icon size change already uses.

A folder that saved its own view keeps it. Finder stores that view, and the folder's icon positions, in a hidden `.DS_Store` file inside the folder, and that file wins over the default. The reset command and the skip list are in [Troubleshooting](troubleshooting.md#a-finder-folder-is-not-sorted-by-name). To fix one folder by hand, open it: **View → Show View Options** (`Command + J`) → **Sort By Name**.

1. Open any Finder window → **View → Show View Options** (`Command + J`)
2. **Icon size** 72×72, **Text size** 13, and **Sort By Name** are the pinned defaults for new icon-view windows. The Desktop is pinned to **Sort By Name** only
3. A folder with its own `.DS_Store` still needs **Sort By Name** set once on that folder, or `macconfig --reset-folder-views` for every folder at once
4. **Use as Defaults** is optional; `macos.sh` already writes the window defaults
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

Cloud backup: sign in to your Logi account first, then **MX Master 3S → Settings → Other** and turn on **Automatically backup all devices**; it shows **Last backup on …** underneath. Use **Restore settings from backup** (same page) on a new Mac if needed. Not readable locally, so manual step `logi-cloud-backup` is by hand.

## Raycast

Raycast is set by hand. The click path is manual steps `raycast-hotkey` and `raycast-clipboard` in [Manual steps](manual-steps.md).

The hotkey is `Shift + Control + Command + R`, not `Option + Space`. Don't click the **Replace Spotlight** button. That turns off Spotlight's Command+Space. `macos.sh` puts Command+Space back when it differs, and so does `macconfig --fix`.

Hammerspoon brings Finder to the front with `Shift + Control + Command + F` ([Modes](modes.md#finder-hotkey)).

## By hand

These stay by hand because nothing reliable can read or write them. The click path is the row in [Manual steps](manual-steps.md).

Charge Limit (manual step `charge-limit`) is 80% on an Apple silicon laptop, from macOS Tahoe 26.4 on. It is not a row on the Battery page: click ⓘ next to Charging, drag Charge Limit to 80% (leave Optimised Battery Charging on), then Done. Apple documents no command that sets it: `pmset` has none, and the Shortcuts action Set Battery Charge Limit is not a shell command. `pmset -g` and `pmset -g custom` show sleep timers and the live battery. `pmset -g battlimit` calls the private `IOPSCopyBatteryLevelLimits` and needs the entitlement `com.apple.private.iokit.soc-limit`, which an unprivileged reader does not have. `ioreg -rn AppleSmartBattery` and `system_profiler SPPowerDataType` show the live charge, not the limit. The power preferences under `/Library/Preferences` and `~/Library` have no user-readable percentage for it. A desktop has no battery. The step stays by hand.

Edge Light (manual step `edge-light`) is Off. It lights the edges of the screen like a ring light during a video call. Start a video call, or open Photo Booth or FaceTime, so the camera is on. Then click Control Centre in the menu bar, click Video Effects, and click Edge Light so it is Off. On this Mac the on/off state is in `~/Library/Group Containers/group.com.apple.secure-control-center-preferences/Library/Preferences/group.com.apple.secure-control-center-preferences.av.plist`, and reading that file is permission denied. RingLightHelper's group (`group.com.apple.ringlight`) holds no preferences. Nothing writes either place. The step can't be checked, so it is always shown. `macconfig` lists it as `MANUAL:`, the same wording `manualsteps` uses.

Center Stage (manual step `zoom-center-stage`) is Off for Zoom. Center Stage moves the picture to keep you in the middle of it as you move. Start a Zoom call, or a test video under Zoom → Settings → Video, with the camera on. Then click the green camera icon in the menu bar, and under MacBook Pro Camera turn off Centre Stage. macOS remembers this per app, so other apps keep their own setting. macOS keeps per-app Video Effects, Center Stage included, in the system camera service, not in a user preference. No `defaults` domain and no plist under `~/Library` holds it. Nothing reads it and nothing writes it. `manualsteps` and `macconfig` label the step `MANUAL: Can't check this automatically. If it's already set, press s.`

Framing (manual step `meet-framing`) is Off in Google Meet. With it on, Meet zooms the built-in MacBook camera in too far. In a Meet call, with the camera on, open Backgrounds and effects, then the Appearance tab, and turn Framing off. The toggle says it puts you in the center of the screen. Settings → Video only says video enhancement has moved and points at Backgrounds and effects. Framing is on that Appearance tab. macOS Centre Stage stays as it is. The value lives in the Meet web app and the Google account. No `defaults` domain and no plist under `~/Library` holds it. Nothing reads a Chrome profile for it and nothing writes one. `manualsteps` and `macconfig` label the step `MANUAL: Can't check this automatically. If it's already set, press s.` The Video page that only points at Backgrounds and effects is in [Troubleshooting](troubleshooting.md#google-meet-framing).

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

**Hammerspoon's config.** The app should be running. `install.sh` starts it after the Brewfile cask and the `hammerspoon/` symlink, with `open -g -a Hammerspoon`, only when the app is installed and not already running. A dry run describes that start and does not open the app. If the `hs` command can talk to it, the repo `hammerspoon/init.lua` is compiled in that process (`loadfile` only, so the config is not run a second time). If `hs` isn't available, the process check stands and `luac` or `lua` syntax-checks the same file. A compile error is a warning. `--fix` starts Hammerspoon through the same helper when it isn't running; it does not rewrite the config.

**com.pdone LaunchAgents.** Every `com.pdone.*` file in `~/Library/LaunchAgents` is compared with the repo template after `@HOME@` is replaced with your home directory. An installed plist with no template is stale or unknown and is a warning. The Dictation, Quick Note, and Game Overlay pin agents are still reported in those sections, and `--fix` can still rewrite those. This extra sweep only reports; it does not write a plist.
