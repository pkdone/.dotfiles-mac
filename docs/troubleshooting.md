# Troubleshooting

See [README.md](../README.md).

The dictation and Quick Note pin values, and the Karabiner rules, are in [Settings](settings.md#keyboard-dictation-fn).

## After a macOS Software Update

**After a macOS Software Update:** Apple often rewrites `com.apple.symbolichotkeys` and resets hotkey 164 to the unbound default (`enabled=0`, `type=standard`, `parameters=(65535,65535,0)`). That is what happened after Tahoe **26.7** / **27.0**. The same rewrite turns Quick Note hotkey 190 back on. Two LaunchAgents (`com.pdone.pin-dictation-hotkey-164` and `com.pdone.pin-quicknote-hotkey-190`) run the pin scripts at login (`RunAtLoad`) and again when `~/Library/Preferences/com.apple.symbolichotkeys.plist` changes (`WatchPaths`). launchd does not expand `~` or `$HOME`, so the repo plists store that path as `@HOME@`. `install.sh` and `macconfig-check.sh --fix` write a regular file under `~/Library/LaunchAgents` with `/Users/<you>` filled in. They are not symlinks. `ThrottleInterval` is 10 seconds, so a burst of writes starts each agent at most once per 10 seconds. Each pin script reads the hotkey and calls `defaults write` only when the value differs. A correct value does not touch the plist, so the watch cannot loop. A repair write changes the plist once more; launchd runs the agent again after the throttle, that run sees the right value and leaves it alone. The weekday drift check and `macos.sh` remain backups. Other managed `defaults` usually survive; this nested hotkey map does not.

## Reloading a LaunchAgent on this Mac

**Reloading a LaunchAgent on this Mac:** launchd keeps the job it last bootstrapped. Saving a new plist does not apply `WatchPaths` until that job is booted out and bootstrapped again. `install.sh` always does both: `scripts/install-launchagent.sh --write`, then `scripts/load-launchagent.sh --reload` (`launchctl bootout gui/<uid>/<label>` if the job is loaded, then `launchctl bootstrap gui/<uid> ~/Library/LaunchAgents/<label>.plist`). `macconfig-check.sh` drifts when the installed file is missing, still a symlink, or different from that rendered copy. `--fix` rewrites it and runs the same bootout/bootstrap. If the file already matches and the job is only not loaded, `--fix` bootstraps it and does not boot out anything. `RunAtLoad` then runs the pin script once; if the hotkey is already correct, that run does not write.

## AC idle sleep

Power settings that need sudo (manual step `ac-sleep`):

- on mains power, the Mac does not sleep on its own (`sudo pmset -c sleep 0`)
- on mains power, the display sleeps after 10 minutes (`sudo pmset -c displaysleep 10`)
- on battery, the display sleeps after 2 minutes (`sudo pmset -b displaysleep 2`)
- on mains power, wake for network access is on (`sudo pmset -c womp 1`)

Closing the lid still sleeps the Mac. Battery idle sleep is not changed. The screen still locks. `macconfig-check.sh` reads `pmset -g custom` and warns when one of those values is different. A company MDM (Kandji) reset often puts the sleep timer back. `--fix` does not run the commands, because they need sudo. `macos.sh` may run them and skips them when sudo is not available or you answer no. Run the manual step again in a terminal.

The `macos.sh` step that runs the same command is in [Settings](settings.md#macos-defaults).

## Software Update, LaunchAgents, and broken links

The security check does not run `softwareupdate`, so it does not sit on the network. Automatic security updates are managed by the employer (MDM). The check says so and does not warn about those toggles. It still reads the local Software Update preferences for a recommended update that has been sitting since a successful check more than 7 days ago. Install that update in System Settings when that warning appears.

A `com.pdone.*` file in `~/Library/LaunchAgents` that does not match the repo, or that has no repo template, is a warning. `--fix` still repairs the two pin agents (dictation and Quick Note) when those sections report drift. It does not delete an unknown plist. Remove that file yourself, or add a template under `launchagents/`, then re-run install.

A symlink under `~/.config`, `~/Library/LaunchAgents`, or a home dotfile that points into this repo but whose target is gone is a warning. `--fix` does not recreate it. Restore the file from git, or run `install.sh` again for the links it manages.

## Recalibrating notification bits

To recalibrate after a macOS update: toggle Allow Notifications for one app, read that app's `flags` again, and set `ALLOW_NOTIFICATIONS_BIT` to the bit that flipped. Then run `./tests/notification-prefs.test.sh`.

To recalibrate the style bits: set Hammerspoon to Banners, then back to Alerts, and point `ALERT_STYLE_BIT` at the bit that is set only for Alerts. Then run `./tests/notification-prefs.test.sh`.

How those bits are read, and what a warning means, is in [Settings](settings.md#notifications).
