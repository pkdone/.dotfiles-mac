# Settings

See [README.md](../README.md).

This is what each managed setting does, and why. Applying them is the [setup walkthrough](setup.md). The by-hand list is [Manual steps](manual-steps.md). After a software update, hotkey pins, and AC sleep are in [Troubleshooting](troubleshooting.md).

## Quiet Apple apps (containment)

System apps (Music, Photos, News, …) can't be deleted (SIP). This repo contains them where scripting is reliable:

- **URL handlers** → Chrome (`handlers.sh` / `lib/url-handlers.list`)
- **GarageBand / iMovie / Pages** removed (`prune-apps.sh`)
- **Photos auto-open on device connect** Off (`com.apple.ImageCapture disableHotPlug` in `lib/macos-defaults.list`)
- **Menu bar:** clock, mode icon, battery percentage, Wi-Fi, Bluetooth, Control Centre, and the third-party icons that stay (Tailscale, 1Password, Granola, Hammerspoon, Fleet Desktop). Spotlight, Focus, Now Playing and Voice Control are hidden (`@host/com.apple.controlcenter` = `8`, Don't Show). Bluetooth stays in the menu bar (`2`, Show in Menu Bar). Battery percentage is On (`BatteryShowPercentage`, boolean; `defaults read` prints `1`). `macos.sh` / `macconfig-check.sh` check those rows; `macconfig --fix` repairs them and restarts ControlCenter. Karabiner's own menu bar icon stays hidden. Raycast, Logi Options+ and Docker are Off under System Settings → Menu Bar → Allow in the Menu Bar (manual step `menubar-third-party-hide`; Raycast's own toggle isn't scriptable)
- **Dock minimize and bounce:** windows minimize into the application icon (`com.apple.dock minimize-to-application` = true) and opening an app does not bounce the icon (`no-bouncing` = true). `macos.sh` / `macconfig-check.sh`; `macconfig --fix` repairs them and restarts Dock
- **Desktop switch delay:** dragging a window to the screen edge still snaps it into place. It moves to the next desktop only after you hold it there for 5 seconds (`com.apple.dock workspaces-edge-delay` = 5). `macos.sh` / `macconfig-check.sh`; `macconfig --fix` repairs it and restarts Dock. Checked on this Mac (Tahoe)
- **Finder sidebar Recents** Off, **icon view 72/13 and Sort By Name**, **show all filename extensions** On, **status bar** On, **sidebar icon size** Large, and **CotEditor** theme **Anura (Dark)** + monospaced font via `macos.sh` / `macconfig-check.sh`
- **Finder and Trash tidy:** remove Trash items after 30 days (`FXRemoveOldTrashItems`), search the current folder (`FXDefaultSearchScope` = `SCcf`), keep folders on top (`_FXSortFoldersFirst`), and no `.DS_Store` on network volumes (`com.apple.desktopservices DSDontWriteNetworkStores`; the domain is created by the first write). `macos.sh` / `macconfig-check.sh`; `macconfig --fix` repairs them and restarts Finder
- **Window tiling (macOS 15+):** drag a window to the left or right edge to tile (`com.apple.WindowManager EnableTilingByEdgeDrag` = true; unset on this Mac, which is the system default On) and no gap between tiled windows (`EnableTiledWindowMargins` = false; `defaults read` prints `0`). `macos.sh` / `macconfig-check.sh`; `macconfig --fix` repairs them. `restart` is empty, so a repair restarts no process. Shortcuts are in [SHORTCUTS.md](../SHORTCUTS.md)
- **Desktop widgets and Stage Manager:** widgets hidden on the desktop and in Stage Manager (`StandardHideWidgets` and `StageManagerHideWidgets` = true; Show Widgets → On Desktop and In Stage Manager off) and Stage Manager off (`GloballyEnabled` = false). `macos.sh` / `macconfig-check.sh`; `macconfig --fix` repairs those three keys through the `defaults` row in `lib/autofix.list`. `restart` is empty, so a repair restarts no process. Hiding a widget does not delete it. Placed widgets are checked separately (manual step `remove-widgets`) and `macconfig --fix` does not remove them. Click wallpaper to reveal desktop (`EnableStandardClickToShowDesktop`) is not pinned
- **Login Items:** `macconfig-check.sh` drifts if ChatGPT is enabled at login (the app may stay installed; turn it **Off** in **System Settings → General → Login Items**). Tailscale must be in Open at Login. It has no launch-at-login option of its own. When `/Applications/Tailscale.app` is installed and missing from that list, the check says: System Settings → General → Login Items & Extensions → under Open at Login click + → Applications → Tailscale → Open. The list is only read. `--fix` does not add it. An uninstalled Tailscale is left alone. Tailscale's team and bundle ids are on `lib/login-items-allow.list`, so that entry is expected. WhatsApp Web (the Safari web app at `~/Applications/WhatsApp Web.app`) is also expected under Open at Login. Its bundle id is different on each Mac, so the list names it by that path, and no other Safari web app is allowed by it

Universal Links like `https://music.apple.com` may still open Apple apps — use Chrome when it matters.

## Keyboard / Dictation / Fn

**Goal:** hold-Fn/Globe must never start the mic (Dictation / Apple Intelligence).

**Scripted + checked** (`macos.sh` / `macconfig-check.sh`):
- Fn/Globe → **Do Nothing** (`AppleFnUsageType` = `0`)
- Dictation **Off**
- Symbolic hotkey 164 ("Start Dictation") pinned to **Right Command twice** — a *dummy* unused combo so Press 🎙️ / Fn never owns it. Do **not** use Right Command twice yourself; it would fire dictation if Dictation were on.
- Symbolic hotkey 190 ("Quick Note") disabled so Globe/Fn+Q does not open Notes (`enabled=0`, `type=standard`, unbound parameters).
- Symbolic hotkey 64 ("Show Spotlight search") stays **Command+Space** (`enabled=1`, `type=standard`, parameters `32, 49, 1048576`). Raycast's Replace Spotlight button turns it off. `macos.sh` writes it only when the value differs. `macconfig --fix` writes the same value and runs `activateSettings -u`. There is no LaunchAgent for it.

What a macOS Software Update does to these hotkeys, and how to reload a LaunchAgent on this Mac, is in [Troubleshooting](troubleshooting.md#after-a-macos-software-update). Command+Space is in [Troubleshooting](troubleshooting.md#spotlight-commandspace).

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

**Logi Options+: checked, never written.** Logi Options+ keeps its settings as JSON inside a private SQLite database (`~/Library/Application Support/LogiOptionsPlus/settings.db`; the agent caches it and syncs it to the mouse). `lib/logi-settings.py` copies the database (plus its `-wal` / `-shm`) to a temp dir, reads the copy read-only, deletes it, and compares the MX Master 3S values (found by model `2b034`, not serial number) with `lib/logi-expected.list`: main wheel Natural + smooth + SmartShift, thumb wheel horizontal scroll + smooth, gesture button window navigation, pointer speed 0.12. The **Logi Options+** section of `macconfig-check.sh` reports drift as **Needs Paul** (`logi-settings` in `lib/autofix.list`; `--fix` never touches it), and a missing app, missing database or unreadable format as a warning (`logi-unreadable`), never a failure of the run. Restore is by hand in the app or from Logi's cloud backup (manual step `logi-cloud-backup`). Cloud backup itself stays **by hand**: the **Automatically backup all devices** toggle and the last-backup time aren't in any readable local file (the per-device `settings_backup_state_v2` flags in `settings.db` stay false with backup on), so there's nothing reliable to check. Manual step `logi-smooth-scrolling` uses the same helper (`logi:<id>` check).

## macOS defaults

> _Run by `bootstrap.sh`; the commands below run only this step._

A curated set of macOS `defaults` is applied by `macos.sh` (plus Dictation hotkey 164, CotEditor theme/font, Finder sidebar Recents, Finder Favorites, the Show Finder shortcut, power settings, the built-in display's More Space mode, and the ARZOPA portable monitor when it is plugged in):

```bash
~/.dotfiles-mac/macos.sh --dry-run   # preview every decision, write nothing
~/.dotfiles-mac/macos.sh             # apply
```

Safe to re-run: it reads each setting first, then writes the desired value (re-asserting even when it already matches). A boolean and an integer 0 or 1 are the same value. A match is left as it is, and a difference is written with the type already stored (`-bool` when the key is a boolean). Any other unexpected type is skipped, with a warning. Missing keys are set. Before the first actual change it backs up each affected domain to `backups/defaults-<timestamp>/`. UI restarts (Dock, Finder, menu bar) happen at the end only when something actually changed, after you confirm.

Dark mode is `NSGlobalDomain` `AppleInterfaceStyle` = `Dark`. `macos.sh` also tells System Events to turn dark mode on immediately when it is not already on, so a logout is not required. If System Events refuses (often a missing Automation permission), that is a warning and the default is still written. `macconfig --fix` uses the same path.

Theme colour is Graphite: System Settings → Appearance → Theme → Colour: Graphite. That is `NSGlobalDomain` `AppleAccentColor` = `-1` (an integer). `macos.sh` writes `-int -1` only when the value differs, the same way it writes dark mode. `macconfig-check.sh` reads that row and reports drift when the accent is missing or is not `-1`. `AppleHighlightColor` is left unset, so the highlight follows the accent. Nothing writes it. Graphite may need a logout, or each app opened again, before it shows everywhere. The needs-logout list at the end of setup includes this accent only when the value changed.

Power is the one `macos.sh` step that uses sudo. It runs only the `pmset` commands that are still wrong: AC sleep 0, AC display sleep 10 minutes, battery display sleep 2 minutes, and AC wake for network access. It is skipped when sudo isn't available (no passwordless sudo and no terminal) or isn't wanted (`--dry-run`, or you answer no at the prompt). Values that already match do not call sudo. `--yes` skips that confirmation and still will not hang waiting for a password when there is no terminal. Battery idle sleep is not changed. Closing the lid still sleeps the Mac. The check warns when one of those values differs, which is what a Fleet reset often does to the sleep timer. `--fix` does not run sudo. See [Troubleshooting](troubleshooting.md#ac-idle-sleep).

Trackpad rows in that list are tap to click (built-in trackpad, Bluetooth trackpad, and `com.apple.mouse.tapBehavior`), click pressure Light, secondary click in the bottom right corner, three-finger drag Off, tracking speed `0.6875`, Force Click and haptic feedback On (`ActuateDetents=1`, `ForceSuppressed=0`), natural scrolling On, swipe-between-pages Off, three-finger tap Off, and the 3/4/5-finger swipe and pinch gestures. On a fresh Mac the 0/1 keys may already be booleans. That matches integer 0 or 1, so it is not a type mismatch, and a wrong value is written with `-bool` when that is the type already stored. The gesture keys are written for both the built-in trackpad and the Bluetooth trackpad. Secondary click stays the bottom-right corner (`TrackpadCornerSecondaryClick` = 2) and a right-side click stays off (`TrackpadRightClick` = 0). Each one sets `restart` to `logout`. When a value changes, `macos.sh` runs `activateSettings -u` when that tool is present, so the trackpad follows the new value without a logout. If it is missing or fails, the change is listed as needing a logout, and `bootstrap.sh` prints that list at the end of setup. `macconfig-check.sh` reads the same list, and `macconfig --fix` repairs drift through the `defaults` row in `lib/autofix.list` and uses the same reload. Look up & data detectors is checked (`com.apple.trackpad.forceClick` = 0) and not written. Mouse tracking speed and scrolling speed stay a check only, because writing them does not stick.

Finder and Trash tidy rows in that list remove Trash items after 30 days (`com.apple.finder FXRemoveOldTrashItems`), search the current folder (`FXDefaultSearchScope` = `SCcf`), keep folders on top (`_FXSortFoldersFirst`), and skip `.DS_Store` on network volumes (`com.apple.desktopservices DSDontWriteNetworkStores`). That domain may not exist until the first write; writing creates it. Those four set `restart` to `Finder`. The Tags group in the sidebar stays closed (`SidebarTagsSctionDisclosedState` = false; Apple's key is spelled that way). Screenshots and screen recordings save to `~/Pictures/Screenshots` (`com.apple.screencapture location`, stored as `@HOME@/Pictures/Screenshots` so apply and check expand `$HOME`), keep the floating thumbnail (`show-thumbnail` = true), use window capture (`style` = `window`), and leave video capture on (`video` = 1). macOS may store video capture as an integer or a boolean. Either one counts as on, the same way as every other 0/1 setting, so that difference is not drift, and `macconfig --fix` leaves an on value alone. `location` is the save folder for both screenshots and recordings. Those keys set `restart` to `SystemUIServer`. `install.sh` creates `~/Pictures/Screenshots` with `mkdir -p`. `macos.sh` does the same before it writes the location, including when `macconfig --fix` repairs that key. Existing screenshots are left where they are.

Finder sidebar Favorites are `lib/sidebar-favorites.list` (Applications, Desktop, Developer, Documents, Downloads, Movies, Music, Pictures). `macos.sh` and `macconfig-check.sh` read `~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.FavoriteItems.sfl4` (or `.sfl3`, or `.sfl2`, whichever file this Mac has) and compare the file favorites with that list. A match is left alone. A difference is a warning. A missing FavoriteItems file is not a warning: Finder may not create it until the sidebar is edited, so that is an info line you check by hand. It is not part of the ok total. Nothing writes the sidebar file: Homebrew has no `mysides` formula or cask, and editing that file directly is not reliable, so `macconfig --fix` does not change Favorites. The Tags group stays collapsed (`SidebarTagsSctionDisclosedState`; Apple spells it that way). Recents stays hidden. Shared stays hidden, AirDrop and iCloud Drive stay hidden, and the Locations rows (your home folder, Macintosh HD, Network, Trash) are checked when the sidebar files name them. A row the files do not name stays by hand. No tags shown in the sidebar is manual step `finder-sidebar-tags`: Finder → Settings → Tags → untick every box under Show these tags in the sidebar. `FavoriteTagNames` is not that list. On this Mac every box is unticked and the sidebar has no Tags section, but `defaults read com.apple.finder FavoriteTagNames` still returns `("", Red, Orange, Yellow, Green, Blue, Purple, Grey)`. Tags sync through iCloud (`TagsCloudSerialNumber`). The check does not read that key and does not warn. `SidebarShowingiCloudDesktop` is still not checked. `macconfig --fix` does not change the sidebar.

Show Finder is the menu shortcut Cmd-Ctrl-Shift-F (`com.apple.finder` `NSUserKeyEquivalents`, added with `-dict-add` so other menu shortcuts stay). Hammerspoon uses the same keys to bring Finder to the front from any app (`hammerspoon/finder_hotkey.lua`). Double-clicking a window's title bar fills the window (`AppleActionOnDoubleClick` = `Fill`). If the older minimize-on-double-click key is set, `macos.sh` deletes it.

The built-in display's More Space mode is set by `macos.sh` with `displayplacer` (Homebrew formula `displayplacer`) when that mode is listed for the panel in `lib/display-resolution.list` (14": `1800 x 1169`, 16": `2056 x 1329`). The current refresh rate is kept when a scaled mode at that rate exists. Other displays are left on their current mode, except the ARZOPA portable monitor: when it is plugged in, the same command sets it to 1920x1080 with scaling off, to the left of the laptop, at 180Hz, or at the highest rate the connection offers when 180Hz is not (144Hz through the StarTech dock). If that rate does not take, the next rate down is tried. The laptop stays at the origin so the Dock and menu bar stay there. A missing `displayplacer` or a missing mode is a warning and stays the manual step (System Settings → Displays). `macconfig --fix` uses the same path. An unlisted panel size, no built-in panel, or an unplugged ARZOPA is left alone.

The desktop picture is Tahoe Night (Landscape). `macconfig-check.sh` looks for asset `CF6347E2-4F81-4410-8892-4830991B6C5A` in the wallpaper store and warns if it is absent. That picture is a wallpaper-catalog asset, not a file under `/System/Library/Desktop Pictures`, so System Events cannot select it. The wallpaper store is not written. `--fix` does not change the picture. Set it by hand in System Settings → Wallpaper.

Automatically adjust brightness stays by hand (System Settings → Displays). It needs an admin password, and the saved value is a root-owned file. `bootstrap.sh` names this step when it prints the manual steps, and the walk-through opens Displays. True Tone and Slightly dim the display on battery are left alone.

The account picture is the Dog. `macconfig-check.sh` hashes the JPEGPhoto on the user account (the same bytes as `dscl . -read /Users/$USER JPEGPhoto | tail -n +2 | xxd -r -p`) and compares it with `lib/user-picture.sha256`. A different picture is a warning. `--fix` does not change it.

Window tiling rows in that list turn on drag-to-edge tiling (`com.apple.WindowManager EnableTilingByEdgeDrag` = true) and turn tiled-window margins off (`EnableTiledWindowMargins` = false). On this Mac the edge-drag key is unset, which is the system default On, and margins read as `0` (boolean false). Both rows leave `restart` empty. WindowManager applies the domain live: writing the margins key moves windows that are already tiled, and the edge-drag key is read on the next drag, so `macos.sh` restarts no process for them. `macconfig-check.sh` reads the same list, and `macconfig --fix` repairs drift through the `defaults` row in `lib/autofix.list`. HideDesktop, drag-to-menu-bar, the Option-drag toggle, and Click wallpaper to reveal desktop (`EnableStandardClickToShowDesktop`) stay out of the list. Moving the window on to the next desktop is separate: `com.apple.dock workspaces-edge-delay` waits 5 seconds at the edge before that happens, and the snap itself is unchanged. Desktop pins in `lib/desktop-bindings.list` stay as they are.

Stage Manager and desktop widgets are three more `com.apple.WindowManager` rows. `StandardHideWidgets` = true and `StageManagerHideWidgets` = true hide widgets (System Settings → Desktop & Dock → Widgets → Show Widgets: On Desktop off, and In Stage Manager off). `GloballyEnabled` = false turns Stage Manager off. Those rows leave `restart` empty too. WindowManager applies the domain live, so `macos.sh` does not `killall Dock` (that reloads Spaces) or WindowManager. `macconfig --fix` repairs them through the same `defaults` row in `lib/autofix.list`. Hiding a widget does not remove it. On this Mac, Calendar, Weather and Photos stayed on the desktop with `StandardHideWidgets` true, and they show again when the desktop is revealed. Placed widgets are the `widgets` → `instances` array in `~/Library/Containers/com.apple.notificationcenterui/Data/Library/Preferences/com.apple.notificationcenterui.plist` (one data blob per widget), next to `DesktopWidgetPlacementStorage`. The **Desktop widgets** section of `macconfig-check.sh` reads that array. A missing or empty `instances` array is ok. One or more instances is a warning (`N widgets on the desktop`, plus a kind bundle id when the nested plist has a readable extension or kind). A plist that cannot be read is check by hand. Removing one is manual step `remove-widgets`: Control-click (or right-click) each widget → Remove Widget. `macconfig --fix` does not write that plist and does not kill NotificationCenter or chronod.

Menu bar rows in that list hide Spotlight, Focus, Now Playing and Voice Control (`@host/com.apple.controlcenter` = `8`, Don't Show), keep Bluetooth in the menu bar (`Bluetooth` = `2`, Show in Menu Bar), and show the battery percentage (`BatteryShowPercentage` = true; `defaults read` prints `1` because the type is boolean). Each of those sets `restart` to `ControlCenter`, the same token Spotlight, Focus and Now Playing already use. `macos.sh` runs `killall ControlCenter` only when a value changed. `macconfig-check.sh` reads the same list, and `macconfig --fix` repairs drift through the `defaults` row in `lib/autofix.list`. The intended menu bar is the clock, the mode icon, battery percentage, Wi-Fi, Bluetooth and Control Centre, plus Tailscale, 1Password, Granola, Hammerspoon and Fleet Desktop. Wi-Fi is already shown and is not pinned here. Raycast, Logi Options+ and Docker are turned off by hand (manual step `menubar-third-party-hide`). Karabiner-Elements stays out of the menu bar via `karabiner.json`.

Dock behavior rows in that list minimize windows into the application icon (`com.apple.dock minimize-to-application` = true) and turn off the bounce when an app opens (`no-bouncing` = true; System Settings → Desktop & Dock → Animate opening applications Off). Both set `restart` to `Dock`, the same as icon size, recent apps, Hot Corners, and the 5 second delay before a window moves to the next desktop (`workspaces-edge-delay`). Icon size stays exactly `28`. A change restarts Dock. `macconfig-check.sh` reads the same list, and `macconfig --fix` repairs drift through the `defaults` row in `lib/autofix.list`. App order stays in `lib/dock-apps.list`: Slack, WhatsApp Web, Granola, Google Chrome, Ghostty, CotEditor, Cursor, Cursor Nightly, Grok Bot, Spotify, YouTube Music. WhatsApp Web is the Safari web app at `~/Applications/WhatsApp Web.app` (manual step `whatsapp-web`). Until that step is done, the Dock check says WhatsApp Web is missing because the manual step hasn't been done, and the other apps are still compared in order. Desktop pins stay in `lib/desktop-bindings.list`. Slack, WhatsApp Web and Granola are Desktop 1. Chrome is Desktop 2. Cursor, Cursor Nightly and Grok Bot are Desktop 3. Spotify and YouTube Music are Desktop 4. Ghostty and CotEditor are not assigned. WhatsApp Web's bundle id is read from the app's Info.plist (`@APP@` in the list), so the UUID Safari generates is not stored in the repo. If the app is missing, that pin is reported as not set up yet and `macconfig --fix` does not write it.

Run `macos.sh --list` to see the exact set of settings it manages (printed as a Markdown table).

## Notifications

Per-app **Allow Notifications** is checked by the **Notifications** section of `macconfig-check.sh`. The apps that must be off are only the seven in `lib/notifications-off.list`: Calendar, FaceTime, Game Center, Home, Tips, Wallet, and Messages. An app in that list whose Allow Notifications is on is a warning (**Needs Paul**). An app that is not in the notification store has never posted a notification, so it cannot be on: that is an info line (`not registered for notifications yet, nothing to turn off`), not a warning. Messages shows **Critical** in System Settings when normal notifications are off and Critical Alerts are still allowed. Bit 25 clear is not a warning, and it is not reported as off. On this Mac `io.tailscale.ipn.macsys` and Logi Options+ were both flags `268443662` (badge, sound, and banner set, bit 25 clear) while System Settings showed Tailscale on (Badges, Sounds, Desktop). Apps that showed as on had flags `310386702` (bit 25 set). A clear bit only says the bit is clear. Hammerspoon's Alerts style is the same read: until Hammerspoon has posted a notification, the style can't be checked, and that is an info line. Hammerspoon being allowed to notify is not a warning. A third-party app (`com.apple.*` and `_SYSTEM_CENTER_*` excluded) that isn't in that list or `lib/notifications-reviewed.list` is an `info` line, so a newly appeared app gets flagged. Cursor, Cursor Nightly, Ghostty, both Google Chrome entries, Grok Bot, Microsoft Teams, Slack, Spotify, Tailscale, Zoom, Santa, and SentinelAgent are reviewed, so on is not a warning. Find My, Finder, Kerberos, and WhatsApp Web are `com.apple.*` ids, so they are ignored. Do not add Santa, SentinelAgent, or Kerberos to the off list. A missing store or a plist that doesn't parse is a warning; the check does not crash.

On macOS 27 the store is `~/Library/Group Containers/group.com.apple.usernoted/Library/Preferences/group.com.apple.usernoted.plist` (binary plist, key `apps`). `~/Library/Preferences/com.apple.ncprefs.plist` is not used. `lib/notification-prefs.py` reads it with `python3` `plistlib` and never writes it. `--fix` does not change it.

Allow Notifications is read from `flags` bit 25 (`1 << 25`). The constant is `ALLOW_NOTIFICATIONS_BIT` in `lib/notification-prefs.py`. That is the bit Hush uses for this same plist on macOS 26, and the bit ncmanager used for the older ncprefs store. On this Mac Chrome (`com.google.Chrome`, flags `41951246`) and later on-rows (flags `310386702`) have the bit set. `310386702` is the older Slack sample `276832270` plus bit 25, and those rows were on. `268443662` is badge, sound, and banner with bit 25 clear. A clear bit is not reported as off.

To recalibrate after a macOS update, see [Troubleshooting](troubleshooting.md#recalibrating-notification-bits).

**Hammerspoon's notification style** is checked in that same read (manual step `mode-hammerspoon-alerts`). Alerts is `flags` bit 4 set and bit 3 clear. Hush names those `alertPersistent` (`1 << 4`) and `alertTemporary` (`1 << 3`) on this usernoted plist; bit 3 alone is Banners, and both clear or both set is None (Hush treats both-set as Off). ncmanager's older ncprefs store uses the same two bits (`style_alerts`, `style_banners`). The constant is `ALERT_STYLE_BIT` (banner bit: `BANNER_STYLE_BIT`). On this Mac Hammerspoon's flags are `8396822`, which is Alerts. Anything else is a warning (**Needs Paul**). `--fix` does not write the store.

To recalibrate the style bits, see [Troubleshooting](troubleshooting.md#recalibrating-notification-bits).

Notification Centre stays by hand. The four controls at the top of System Settings → Notifications are Show previews **When Unlocked**, **when display is sleeping** off, **when screen is locked** on, and **Notifications Off** when mirroring or sharing the display (manual steps `notifications-previews`, `notifications-display-sleep`, `notifications-lock-screen`, `notifications-mirroring`). They are not the per-app flags. An app's own preview (`content_visibility`: Default, Never, When Unlocked, Always) is a different control. `~/Library/Preferences/com.apple.ncprefs.plist` is not the store on macOS 27. No key in the usernoted plist has been shown to match those four controls, so the check does not read them and does not warn when a guessed key is missing. Nothing writes them. `manualsteps` and `macconfig` label each one `MANUAL: Can't check this automatically. If it's already set, press s.` When one of the seven apps is still on, that reason line is `NOTSET:` and the check's detail.

## Finder

Per-window View Options and chrome. The default icon view is pinned by `macos.sh` and checked by `macconfig-check.sh`: icon size 72, text size 13, and Sort By Name (`arrangeBy` = `name`) on `StandardViewSettings` and `FK_StandardViewSettings`. The Desktop (`DesktopViewSettings`) is not changed. A value is written only when it differs, and a full run re-asserts it when it already matches. Finder is restarted with `killall Finder`, the same restart the icon size change already uses. A folder that saved its own view in `.DS_Store` does not pick this up. Open that folder and set it once: **View → Show View Options** (`Command + J`) → **Sort By Name**.

1. Open any Finder window → **View → Show View Options** (`Command + J`)
2. **Icon size** 72×72, **Text size** 13, and **Sort By Name** are the pinned defaults for new icon-view windows
3. A folder with its own `.DS_Store` still needs **Sort By Name** set once on that folder
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

Raycast is set by hand.

Move Raycast off `Option + Space` (clashes with ChatGPT). Open Raycast → Settings (Command+,) → General → **Raycast Hotkey** → click the hotkey recorder and press `Shift + Control + Command + R`. Don't click the **Replace Spotlight** button next to it. That turns off Spotlight's Command+Space. `macos.sh` puts Command+Space back when it differs, and so does `macconfig --fix`.

Clipboard History:

1. Open Raycast, run **Clipboard History** once, and allow Accessibility if asked.
2. Raycast Settings → **Clipboard History** in the left sidebar. There is no Extensions tab.
3. Set **Keep history for** to 1 Day.
4. Under **Disabled Applications**, click + and add 1Password and 1Password for Safari. Keychain Access and Passwords are already listed.
5. In **Commands**, on the Clipboard History row, click **Add Hotkey** and press `Control + Command + V`. Avoid `Command + Shift + V` (paste without formatting) and `Command + Option + V` (Finder paste-as-move).

Hammerspoon brings Finder to the front with `Shift + Control + Command + F` ([Shortcuts](../SHORTCUTS.md#hammerspoon)).

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
