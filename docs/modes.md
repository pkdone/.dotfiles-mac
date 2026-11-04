# Modes

See [README.md](../README.md).

## Modes (menu-bar switcher)

A Hammerspoon menu-bar dropdown switches between three modes. Switching is **manual only**: no hotkey, no automatic triggers. Settings are in [`hammerspoon/modes.lua`](../hammerspoon/modes.lua) (a commented Lua table); the engine is `hammerspoon/mode_switcher.lua`, loaded from `init.lua`.

| Mode | Icon | What it does |
|------|------|------|
| **Normal** | 🖥 `desktopcomputer` | Undoes whatever the last mode recorded: reopens apps it quit (in the background, not hidden), unhides apps it hid, turns its Focus off, lets the display sleep again. Notification badges come back with the Focus. |
| **WebConf** (on air) | red ⏺ `record.circle.fill` | Quits Spotify, YouTube Music (Chrome app `com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod`), and WhatsApp Web; hides Slack, Finder windows and Grok Bot; WebConf Focus on; keeps the display awake; brings Granola to the front. Keeps the Dock. |
| **DeepWork** | `brain.head.profile` + time left (e.g. `42m`) | Quits Slack and WhatsApp Web, hides Granola, DeepWork Focus on, leaves Spotify alone. Counts down 50 min (`timerMinutes`); at the end a notification offers **Take a break** / **Back to Normal** / **Another session** (it never switches by itself). |

WhatsApp Web is the Safari web app at `~/Applications/WhatsApp Web.app` (manual step `whatsapp-web`), not the WhatsApp app. WebConf and DeepWork quit that web app and leave Safari itself running. If WhatsApp Web is not installed, or it is not running, the mode skips it. Switching from one of those modes to the other leaves it quit. Normal opens it again in the background, the same way it reopens any other app a mode quit.

The dropdown ticks the current mode. Under the tick, a disabled line says why you're in it: `WebConf · 12m · Focus on`, `DeepWork · 42m left · Focus on` (time left while the timer is running; otherwise how long the mode has been on), or `Normal · restored`. Focus on/off is included when the switcher knows it. When Focus Shortcuts are missing, one clickable item lists them, copies the names, and opens Shortcuts. The menu still notes anything skipped, and has **Dry run** (prints what a mode would do to the Hammerspoon Console, changes nothing) and **Open switch log**. The icon's tooltip names the mode.

**Safety rails**

- `~/Library/Application Support/pdone-modes/state.json` records the mode and what it changed, written **before** anything changes. After a Hammerspoon reload or a reboot the switcher reads it, shows the persisted mode (re-applying display-awake and the timer), and Normal can still undo everything.
- Switching from one non-Normal mode to another runs Normal's restore first.
- Apps are quit politely (`hs.application:kill()`, like Command-Q), never forced. An app with unsaved work, or one that doesn't quit, is left running and you're told.
- Every switch is logged to `~/Library/Logs/pdone-modes.log` (time, mode, how long the previous mode lasted).
- Menu-bar notification badges can't be switched off (macOS has no API for it), so the Focus is what hides them.

**Focus modes.** Create WebConf and DeepWork once. The click path is manual step `mode-focus-modes` in [Manual steps](manual-steps.md). WebConf allows Granola. DeepWork allows Hammerspoon, so the end-of-session notification gets through.

**Focus needs Shortcuts.** macOS doesn't let apps set a Focus, so the switcher runs four Shortcuts you create once, each with one **Set Focus** action. The click path is manual step `mode-focus-shortcuts` in [Manual steps](manual-steps.md). If any of the Focus shortcuts are missing, the mode still runs. The menu item **Create missing: …** copies those Shortcut names and opens Shortcuts. The switch also shows a short alert naming the Shortcut, for example `WebConf Focus skipped — create 'Mode WebConf On' in Shortcuts`, so you notice without opening the menu. A Shortcut that is present does not raise that alert. `macconfig-check.sh` (section **Modes (Hammerspoon)**) checks that the Shortcuts and the WebConf / DeepWork Focus modes exist, that `modes.lua` is valid, and warns if a non-Normal mode has been on for more than `HEALTH_MODE_MAX_HOURS` (4). Apps a mode quit or hid on purpose are listed as info, never drift.

From a terminal:

```bash
hs -c "return loaded.mode_switcher.status()"
hs -c "return loaded.mode_switcher.dryRun('WebConf')"   # or DeepWork / Normal; changes nothing
hs -c "loaded.mode_switcher.switch('Normal')"
```

## Slack on the ARZOPA monitor

`external_slack.lua` puts Slack on the ARZOPA portable monitor:

- **The monitor connects** (a screen whose name is exactly `ARZOPA`, ignoring case, including when it is already connected as Hammerspoon starts): Slack's main window moves onto that screen and goes full screen. Slack's zoom is left alone.
- **The monitor disconnects:** Slack leaves full screen, comes back to the built-in display, and returns to the size and position it had before the move when that frame still fits.
- Does nothing if Slack isn't running. Screen changes are debounced, and only a real connect or disconnect acts. The Dock and menu bar stay on the built-in display.
- **Manual toggle / test:** `Shift + Control + Option + Command + S`.
- Screen names are logged to the Hammerspoon Console (menu-bar icon → Console). Status from a terminal: `hs -c 'loaded.external_slack.status()'`. If the panel shows up under another name: `hs -c "hs.settings.set('external_slack.screenNames', {'ARZOPA'}); hs.reload()"`.
- `macconfig-check.sh` drifts if the `~/.hammerspoon` symlink or the cask is missing, warns if Hammerspoon isn't running, and (Manual steps section) warns if it lacks Accessibility. `macos.sh` / `macconfig-check.sh` also manage its Dock-icon and crash-upload prefs (`lib/macos-defaults.list`).

The display mode itself is in [Settings](settings.md#macos-defaults). Accessibility is manual step `hammerspoon-ax` in [Manual steps](manual-steps.md). Test by plugging the ARZOPA monitor in and unplugging it. Restart Hammerspoon after granting Accessibility (it can't move windows without it), then menu-bar icon → **Reload Config**.

## Finder hotkey

`finder_hotkey.lua` brings Finder to the front from any app. `Shift + Control + Command + F` launches Finder, or focuses it when it is already running (`hs.application.launchOrFocus("Finder")`). Hammerspoon owns that shortcut. The same keys are the Finder menu shortcut. It is also in [Shortcuts](../SHORTCUTS.md#hammerspoon).
