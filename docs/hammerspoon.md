# Hammerspoon

See [README.md](../README.md).

Hammerspoon runs `external_slack.lua` and `finder_hotkey.lua`. `init.lua` loads them. There is no menu-bar icon and no Dock icon. Open Hammerspoon from Spotlight or Raycast to show its Preferences. The Console is `hs -c 'hs.openConsole()'`. Reload is `hs -c 'hs.reload()'`.

## Slack on the ARZOPA monitor

`external_slack.lua` puts Slack on the ARZOPA portable monitor:

- **The monitor connects** (a screen whose name is exactly `ARZOPA`, ignoring case, including when it is already connected as Hammerspoon starts): Slack's main window moves onto that screen and goes full screen. Slack's zoom is left alone.
- **The monitor disconnects:** Slack leaves full screen, comes back to the built-in display, and returns to the size and position it had before the move when that frame still fits.
- Does nothing if Slack isn't running. Screen changes are debounced, and only a real connect or disconnect acts. The Dock and menu bar stay on the built-in display.
- **Manual toggle / test:** `Shift + Control + Option + Command + S`.
- Screen names are logged to the Hammerspoon Console. Open it with `hs -c 'hs.openConsole()'`. Status from a terminal: `hs -c 'loaded.external_slack.status()'`. If the panel shows up under another name: `hs -c "hs.settings.set('external_slack.screenNames', {'ARZOPA'}); hs.reload()"`.
- `macconfig-check.sh` drifts if the `~/.hammerspoon` symlink or the cask is missing, warns if Hammerspoon isn't running, and (Manual steps section) warns if it lacks Accessibility. `macos.sh` / `macconfig-check.sh` also manage its Dock icon, menu-bar icon, and crash-upload prefs (`lib/macos-defaults.list`).

The display mode itself is in [Settings](settings.md#macos-defaults). Accessibility is manual step `hammerspoon-ax` in [Manual steps](manual-steps.md). Test by plugging the ARZOPA monitor in and unplugging it. Restart Hammerspoon after granting Accessibility (it can't move windows without it), then reload with `hs -c 'hs.reload()'`, or open Hammerspoon from Spotlight or Raycast and choose Reload Config.

## Finder hotkey

`finder_hotkey.lua` brings Finder to the front from any app. `Shift + Control + Command + F` launches Finder, or focuses it when it is already running (`hs.application.launchOrFocus("Finder")`). Hammerspoon owns that shortcut. The same keys are the Finder menu shortcut. It is also in [Shortcuts](../SHORTCUTS.md#hammerspoon).
