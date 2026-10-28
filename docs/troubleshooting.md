# Troubleshooting

See [README.md](../README.md).

The dictation and Quick Note pin values, Spotlight's Command+Space, and the Karabiner rules, are in [Settings](settings.md#keyboard-dictation-fn).

## After a macOS Software Update

**After a macOS Software Update:** Apple often rewrites `com.apple.symbolichotkeys` and resets hotkey 164 to the unbound default (`enabled=0`, `type=standard`, `parameters=(65535,65535,0)`). That is what happened after Tahoe **26.7** / **27.0**. The same rewrite turns Quick Note hotkey 190 back on. Two LaunchAgents (`com.pdone.pin-dictation-hotkey-164` and `com.pdone.pin-quicknote-hotkey-190`) run the pin scripts at login (`RunAtLoad`) and again when `~/Library/Preferences/com.apple.symbolichotkeys.plist` changes (`WatchPaths`). launchd does not expand `~` or `$HOME`, so the repo plists store that path as `@HOME@`. `install.sh` and `macconfig-check.sh --fix` write a regular file under `~/Library/LaunchAgents` with `/Users/<you>` filled in. They are not symlinks. `ThrottleInterval` is 10 seconds, so a burst of writes starts each agent at most once per 10 seconds. Each pin script reads the hotkey and calls `defaults write` only when the value differs. A correct value does not touch the plist, so the watch cannot loop. A repair write changes the plist once more; launchd runs the agent again after the throttle, that run sees the right value and leaves it alone. The weekday drift check and `macos.sh` remain backups. Other managed `defaults` usually survive; this nested hotkey map does not. The same rewrite can turn off Spotlight's Command+Space (hotkey 64). That one has no LaunchAgent. `macconfig --fix` writes it back. See [Spotlight Command+Space](#spotlight-commandspace).

## Spotlight Command+Space

**Command+Space should open Spotlight.** That is symbolic hotkey 64: enabled, type standard, parameters (32, 49, 1048576). Raycast's hotkey recorder has a Replace Spotlight button next to Raycast Hotkey. Clicking it turns hotkey 64 off (`enabled=0`), and Command+Space stops opening Spotlight.

There is no LaunchAgent for this hotkey. Dictation (164) and Quick Note (190) are re-pinned at login. Spotlight is not. `macos.sh` sets hotkey 64 only when it differs. `macconfig --fix` writes it and runs `activateSettings -u`.

To put it back by hand: System Settings → Keyboard → Keyboard Shortcuts… → Spotlight → tick Show Spotlight search (Command+Space) → Done.

## Reloading a LaunchAgent on this Mac

**Reloading a LaunchAgent on this Mac:** launchd keeps the job it last bootstrapped. Saving a new plist does not apply `WatchPaths` until that job is booted out and bootstrapped again. `install.sh` always does both: `scripts/install-launchagent.sh --write`, then `scripts/load-launchagent.sh --reload` (`launchctl bootout gui/<uid>/<label>` if the job is loaded, then `launchctl bootstrap gui/<uid> ~/Library/LaunchAgents/<label>.plist`). `macconfig-check.sh` drifts when the installed file is missing, still a symlink, or different from that rendered copy. `--fix` rewrites it and runs the same bootout/bootstrap. If the file already matches and the job is only not loaded, `--fix` bootstraps it and does not boot out anything. `RunAtLoad` then runs the pin script once; if the hotkey is already correct, that run does not write.

## AC idle sleep

Power settings that need sudo (manual step `ac-sleep`):

- on mains power, the Mac does not sleep on its own (`sudo pmset -c sleep 0`)
- on mains power, the display sleeps after 10 minutes (`sudo pmset -c displaysleep 10`)
- on battery, the display sleeps after 2 minutes (`sudo pmset -b displaysleep 2`)
- on mains power, wake for network access is on (`sudo pmset -c womp 1`)

Closing the lid still sleeps the Mac. Battery idle sleep is not changed. The screen still locks. `macconfig-check.sh` reads `pmset -g custom` and warns when one of those values is different. A Fleet reset often puts the sleep timer back. `--fix` does not run the commands, because they need sudo. `macos.sh` may run them and skips them when sudo is not available or you answer no. Run the manual step again in a terminal.

The `macos.sh` step that runs the same command is in [Settings](settings.md#macos-defaults).

## Software Update, LaunchAgents, and broken links

The security check does not run `softwareupdate`, so it does not sit on the network. Automatic security updates are managed by the employer (MDM). The check says so and does not warn about those toggles. It still reads the local Software Update preferences for a recommended update that has been sitting since a successful check more than 7 days ago. Install that update in System Settings when that warning appears.

A `com.pdone.*` file in `~/Library/LaunchAgents` that does not match the repo, or that has no repo template, is a warning. `--fix` still repairs the two pin agents (dictation and Quick Note) when those sections report drift. It does not delete an unknown plist. Remove that file yourself, or add a template under `launchagents/`, then re-run install.

A symlink under `~/.config`, `~/Library/LaunchAgents`, or a home dotfile that points into this repo but whose target is gone is a warning. `--fix` does not recreate it. Restore the file from git, or run `install.sh` again for the links it manages.

## Windows fill under the Dock

The Dock is showing, but double-clicking a title bar (Fill) makes the window go under it. macOS has stopped keeping space for the Dock. This can happen after a macOS update or after a display is plugged back in. On the MacBook, the screen is 1800x1169 and the usable area was 1800x1130, so only the menu bar was taken off. After the Dock was restarted, the usable area was 1800x1082: the Dock got its 48 points back.

`macconfig` warns about this in the Dock section: "The Dock is showing but macOS isn't keeping space for it, so Fill puts windows under it". It checks only when the Dock does not hide itself. It compares each screen's usable area with its full size on the Dock's side (bottom, left or right). It asks Hammerspoon when Hammerspoon is running, and otherwise macOS directly. If neither answers, or if a full-screen app hides the menu bar too, nothing is reported. `macconfig --fix` restarts the Dock (`killall Dock`; macOS starts it again at once), waits up to 10 seconds, and measures again. To do it by hand, run `killall Dock` in a terminal.

## Docker Desktop and fish/config.fish

On its first start, Docker Desktop may put its own block at the top of `~/.config/fish/config.fish`, which is a link to this repo's `fish/config.fish`. The block starts with the comment "The following lines were added by Docker Desktop" and adds a fixed `export PATH` line with your home folder in it. Don't commit it. `fish/config.fish` already adds `~/.docker/bin` the fish way, after Homebrew, and only when that folder exists. Delete Docker's block, from its first comment through "End of Docker Desktop section". `macconfig` warns under Login shell while the block is there. `--fix` does not remove it, because it never edits repo files.

Docker Desktop's CLI tools setting is under Settings → Advanced. User keeps the tools in `~/.docker/bin`, the folder `config.fish` adds. System links them into `/usr/local/bin` instead and asks for the Mac password.

## Recalibrating notification bits

To recalibrate after a macOS update: toggle Allow Notifications for one app, read that app's `flags` again, and set `ALLOW_NOTIFICATIONS_BIT` to the bit that flipped. Then run `./tests/notification-prefs.test.sh`.

To recalibrate the style bits: set Hammerspoon to Banners, then back to Alerts, and point `ALERT_STYLE_BIT` at the bit that is set only for Alerts. Then run `./tests/notification-prefs.test.sh`.

How those bits are read, and what a warning means, is in [Settings](settings.md#notifications).
