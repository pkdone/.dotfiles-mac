# Modes

See [README.md](../README.md).

## Modes (menu-bar switcher)

A Hammerspoon menu-bar dropdown switches between three modes. Switching is **manual only**: no hotkey, no automatic triggers. Settings are in [`hammerspoon/modes.lua`](../hammerspoon/modes.lua) (a commented Lua table); the engine is `hammerspoon/mode_switcher.lua`, loaded from `init.lua`.

| Mode | Icon | What it does |
|------|------|------|
| **Normal** | 🖥 `desktopcomputer` | Undoes whatever the last mode recorded: reopens apps it quit (in the background, not hidden), unhides apps it hid, turns its Focus off, lets the display sleep again. Notification badges come back with the Focus. |
| **WebConf** (on air) | red ⏺ `record.circle.fill` | Quits Spotify and YouTube Music (Chrome app `com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod`); hides Slack, Finder windows and Grok Bot; WebConf Focus on; keeps the display awake; brings Granola to the front. Keeps the Dock. |
| **DeepWork** | `brain.head.profile` + time left (e.g. `42m`) | Quits Slack, hides Granola, DeepWork Focus on, leaves Spotify alone. Counts down 50 min (`timerMinutes`); at the end a notification offers **Take a break** / **Back to Normal** / **Another session** (it never switches by itself). |

The dropdown ticks the current mode. Under the tick, a disabled line says why you're in it: `WebConf · 12m · Focus on`, `DeepWork · 42m left · Focus on` (time left while the timer is running; otherwise how long the mode has been on), or `Normal · restored`. Focus on/off is included when the switcher knows it. When Focus Shortcuts are missing, one clickable item lists them, copies the names, and opens Shortcuts. The menu still notes anything skipped, and has **Dry run** (prints what a mode would do to the Hammerspoon Console, changes nothing) and **Open switch log**. The icon's tooltip names the mode.

**Safety rails**

- `~/Library/Application Support/pdone-modes/state.json` records the mode and what it changed, written **before** anything changes. After a Hammerspoon reload or a reboot the switcher reads it, shows the persisted mode (re-applying display-awake and the timer), and Normal can still undo everything.
- Switching from one non-Normal mode to another runs Normal's restore first.
- Apps are quit politely (`hs.application:kill()`, like Command-Q), never forced. An app with unsaved work, or one that doesn't quit, is left running and you're told.
- Every switch is logged to `~/Library/Logs/pdone-modes.log` (time, mode, how long the previous mode lasted).
- Menu-bar notification badges can't be switched off (macOS has no API for it), so the Focus is what hides them.

**Focus modes.** Create WebConf and DeepWork once: System Settings → Focus → click Add Focus… (opens a sheet) → Custom → name it WebConf (or DeepWork) → pick any icon → Done → Allowed Apps → Add. WebConf allows Granola. DeepWork allows Hammerspoon, so the end-of-session notification gets through. Allowed People can stay None. An app only appears in that Add list after it has asked macOS for notification permission at least once, so open the app and allow notifications first.

**Focus needs Shortcuts.** macOS doesn't let apps set a Focus, so the switcher runs four Shortcuts you create once, each with one **Set Focus** action. In Shortcuts, click + in the toolbar, click the title at the top and rename it exactly, then in Search Actions on the right type Set Focus and double-click it. Click the blue placeholder words to set them, then close the window to save. The action starts as Turn Do Not Disturb On, so click Do Not Disturb and pick WebConf or DeepWork. The name has to match exactly: `Mode WebConf On` is Turn WebConf On until Turned Off, `Mode WebConf Off` is Turn WebConf Off, `Mode DeepWork On` is Turn DeepWork On until Turned Off, and `Mode DeepWork Off` is Turn DeepWork Off. If any of the Focus shortcuts are missing, the mode still runs. The menu item **Create missing: …** copies those Shortcut names and opens Shortcuts. The switch also shows a short alert naming the Shortcut, for example `WebConf Focus skipped — create 'Mode WebConf On' in Shortcuts`, so you notice without opening the menu. A Shortcut that is present does not raise that alert. The manual steps `mode-*` in [Manual steps](manual-steps.md) walk through it, and `macconfig-check.sh` (section **Modes (Hammerspoon)**) checks that the Shortcuts and the WebConf / DeepWork Focus modes exist, that `modes.lua` is valid, and warns if a non-Normal mode has been on for more than `HEALTH_MODE_MAX_HOURS` (4). Apps a mode quit or hid on purpose are listed as info, never drift.

From a terminal:

```bash
hs -c "return loaded.mode_switcher.status()"
hs -c "return loaded.mode_switcher.dryRun('WebConf')"   # or DeepWork / Normal; changes nothing
hs -c "loaded.mode_switcher.switch('Normal')"
```
