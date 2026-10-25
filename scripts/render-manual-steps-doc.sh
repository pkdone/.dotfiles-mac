#!/usr/bin/env bash
#
# render-manual-steps-doc.sh — write docs/manual-steps.md from lib/manual-steps.list.
#
# The checklist table is `scripts/manual-steps.sh list --markdown`. The notes around
# it are the manual-steps write-up (the same sentences that used to sit in the README).
# Edit those notes here, edit steps in lib/manual-steps.list, then re-run this script.
# tests/manual-steps.test.sh fails when docs/manual-steps.md is stale.
#
#   scripts/render-manual-steps-doc.sh            write docs/manual-steps.md
#   scripts/render-manual-steps-doc.sh --stdout   print the doc
#   scripts/render-manual-steps-doc.sh --check    exit 1 when the file is stale
#
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$DOTDIR/docs/manual-steps.md"
MS="$DOTDIR/scripts/manual-steps.sh"

usage() {
  cat <<'USAGE'
Usage: scripts/render-manual-steps-doc.sh [--stdout|--check]
  (no flag)   Write docs/manual-steps.md from lib/manual-steps.list.
  --stdout    Print the doc instead of writing it.
  --check     Exit 1 if docs/manual-steps.md differs from a fresh render.
  -h, --help  Show this help.
USAGE
}

render() {
  cat <<'EOF'
# Manual steps

See [README.md](../README.md).

> _Manual — no script can do these. `install.sh` prints this checklist when it finishes. `bootstrap.sh` prints the steps that are not set yet, or that can't be checked, and on a terminal offers to walk through them._

Some setup stays manual: privacy permissions (TCC / DriverKit), sign-ins, Fleet apps, and settings that aren't a single reliable `defaults` write (Notification Centre show previews, display sleeping, the lock screen, and mirroring, a Finder sidebar row the sidebar files do not name, mouse double-click and secondary click, the Menu Bar allow-list for Raycast, Logi Options+ and Docker, the Control Centre tiles, the battery charge limit, and Automatically adjust brightness). The account picture, the desktop picture, and the Finder sidebar rows the files do name are checked and not changed. **`lib/manual-steps.list` is the single source of truth** for them; `scripts/manual-steps.sh` reads it. Per-app Allow Notifications is checked by `macconfig-check.sh` (see [Notifications](settings.md#notifications)). Built-in display More Space is set by `macos.sh` with `displayplacer` when that mode is listed (see below). Automatically adjust brightness stays by hand under System Settings → Displays when it is on, or when the check can't read it. Spotlight → Results from Apps is checked by hand: the toggles are not in a preference the check can read, so nothing is written. Look up & data detectors is checked and not written. Trackpad tap to click, click pressure, secondary click, three-finger drag, tracking speed, Force Click, and the gesture keys are applied by `macos.sh` (see [macOS defaults](settings.md#macos-defaults)).

This file is generated from `lib/manual-steps.list`. Edit the list, then run `scripts/render-manual-steps-doc.sh`.

Hammerspoon, Karabiner-Elements, and Raycast are under System Settings → Privacy & Security → Accessibility. Open the app first. It appears in Accessibility or Driver Extensions only after it has asked. If an Accessibility app is still not listed, click + and add it from Applications. Company apps come from Fleet (Fleet Desktop menu bar → My device → Self service).

`manualsteps` is the fish function for `scripts/manual-steps.sh`, installed with the others in `fish/functions/`. With no arguments it runs `check`. Any arguments pass through (`manualsteps list`, `manualsteps pending`, `manualsteps open`, `manualsteps open --all`, `manualsteps check`, `manualsteps --help`), and the exit status is the script's.

```bash
manualsteps          # check (no arguments): ok / warn / by hand (also the "Manual steps" section of macconfig-check.sh)
manualsteps open     # walk through the steps not yet done, opening each System Settings page (terminal only; --all for every step)
manualsteps list     # numbered checklist (every step)
manualsteps pending  # only steps that are not set, or that can't be checked
~/.dotfiles-mac/scripts/manual-steps.sh list    # numbered checklist (same as manualsteps list)
~/.dotfiles-mac/scripts/manual-steps.sh open    # walk through the steps not yet done, opening each System Settings page (terminal only; --all for every step)
~/.dotfiles-mac/scripts/manual-steps.sh check   # read-only: ok / warn / by hand (same as manualsteps)
```

`open` and `pending` tell you why each step is on the screen, on a line under the title and before where to click. That line starts with one word. `NOTSET:` means the step has a check and the check found the setting missing or wrong. The rest of the line is the check's detail, in yellow, and it starts with a capital letter. `MANUAL:` means the step can't be checked automatically. The detail keeps what the check could already read and what is still by hand, starts with a capital letter, and ends with `If it's already set, press s.` A step with no check says `MANUAL: Can't check this automatically. If it's already set, press s.` Edge Light says `MANUAL: Can't be checked, so always shown. If it's already set, press s.`, because its on/off state cannot be read, so that step is always on the list. `macconfig` uses that same `MANUAL:` line for a step it can't check. With `--all`, a step whose check already passed says `Already done, shown because of --all`. The walk-through uses the check it just ran. It does not check the step again.

A step whose check is `@macconfig:<area>` uses the same read-only check as that section of `macconfig-check.sh` (Focus modes, Focus Shortcuts, notifications, and the others listed in `lib/manual-steps.list`). `manualsteps check` and `manualsteps open` report that result, so a Focus mode that is not created yet shows up as not set. When `macconfig` itself is running, those steps stay in their own section and are not listed again under Manual steps.

`check` never writes a setting or prompts, and wraps every slow call in a timeout. It verifies what it can reliably read: privacy grants from the system TCC database (needs Full Disk Access for the terminal or agent running it, otherwise those become "by hand"), pointer size, Accessibility trackpad dragging (`Dragging=1`, `DragLock=0`), Look up & data detectors (`com.apple.trackpad.forceClick` = 0), mouse tracking speed `1.5` (7th notch from Slow) and scrolling speed `0.5` (5th notch from Slow) (check only; `defaults write` does not reliably drive System Settings → Mouse), the Karabiner driver, the Hammerspoon grant (live via `hs`), installed apps, Logi Options+ values (from a temp copy of its settings database), `gh auth status`, and the 1Password CLI (`op whoami`, otherwise a count of accounts from `op account list`). Spotlight → Results from Apps is reported as check by hand. Edge Light is reported as check by hand too: the on/off state cannot be read, so the step is always shown. Steps marked `macconfig-check.sh` below are verified by their own `macconfig-check.sh` section. To add a step, add a row to `lib/manual-steps.list` (format in its header) and regenerate this file with `scripts/render-manual-steps-doc.sh` (the table is `scripts/manual-steps.sh list --markdown`).

British input (`com.apple.HIToolbox` `AppleEnabledInputSources` and `AppleSelectedInputSources`, the keyboard layout name must be British only; Press and Hold and similar non-layout entries are fine; step `input-british`), pointer size (step `pointer-size`), `gh auth status` (step `gh-auth`), and the 1Password CLI (step `1password-cli`) are those same `scripts/manual-steps.sh` checks. `macconfig-check.sh` prints them in the Manual steps section and does not run them a second time. A miss is a warning tagged with the step id (Needs Paul), the same way as `mouse-settings`. `--fix` does not change them. There is no sudo, and the notification store is not written. `op whoami` succeeding means this terminal is signed in. If it fails, `op account list --format=json` is piped into a counter inside the timeout. Only the number of accounts is kept: the body is not stored in a shell variable, a log, or a temp file. One or more accounts means the integration is set up (a new terminal asks to unlock on first use), so the step is not shown. No account is a warning. The check never runs `op signin`, never prompts, and never prints account ids, emails, UUIDs, or URLs.

EOF
  "$MS" list --markdown
  cat <<'EOF'

Trackpad tap to click, click pressure Light, secondary click in the bottom right corner, three-finger drag Off, tracking speed `0.6875`, Force Click and haptic feedback On, natural scrolling, and the 3/4/5-finger gestures are in `lib/macos-defaults.list` (`macos.sh` / `macconfig-check.sh`; `macconfig --fix` repairs them). The same values are written for the built-in trackpad and the Bluetooth trackpad. After a trackpad value changes, `macos.sh` runs `activateSettings -u` when that tool is present, so the trackpad follows the new value without a logout. If it is missing or fails, `bootstrap.sh` says to log out and back in. Look up & data detectors is the check in the table above (`com.apple.trackpad.forceClick` = 0). `ActuateDetents` and `ForceSuppressed` only cover Force Click and haptic feedback, both On. Use trackpad for dragging stays a check (`Dragging=1`, `DragLock=0`: On, without drag lock) because that Accessibility setting does not reliably follow `defaults write`.

Mouse tracking speed (`NSGlobalDomain` `com.apple.mouse.scaling` = `1.5`, the 7th notch from Slow) and scrolling speed (`com.apple.scrollwheel.scaling` = `0.5`, the 5th notch from Slow) are the same kind of check. `macconfig-check.sh` warns when they drift (`mouse-settings` in `lib/autofix.list`, Needs Paul). `--fix` does not write them: on recent macOS those System Settings → Mouse sliders do not reliably follow `defaults write`. Leave Double-Click Speed, Click Right Side and Natural scrolling as they are. The double-click threshold key is unset on this Mac, so it cannot be checked. Logi Options+ sets the wheel direction.

Desktop widgets and Stage Manager are in `lib/macos-defaults.list` too (`StandardHideWidgets` and `StageManagerHideWidgets` = true, `GloballyEnabled` = false). `macos.sh` applies them and `macconfig --fix` repairs them. `restart` is empty, so a repair restarts no process. Click wallpaper to reveal desktop is not pinned.

Hiding widgets does not remove them. Placed widgets are `widgets` → `instances` in `~/Library/Containers/com.apple.notificationcenterui/Data/Library/Preferences/com.apple.notificationcenterui.plist` (one data blob per widget), and they still appear when the desktop is revealed. Manual step `remove-widgets` is that removal: Control-click (or right-click) each widget → Remove Widget. The check is read-only. `macconfig --fix` does not write that plist and does not kill NotificationCenter or chronod. `manualsteps open` shows the step only when a widget is still placed.

Built-in display **More Space** is checked by the **Display (More Space)** section of `macconfig-check.sh`, and set by `macos.sh` (and `macconfig --fix`) with `displayplacer`. The check reads `system_profiler SPDisplaysDataType -json`, finds the built-in panel's size, and looks up its More Space value in `lib/display-resolution.list`: `1800 x 1169` for the 14" panel (3024x1964) and `2056 x 1329` for the 16" panel (3456x2234). It warns when `_spdisplays_resolution` does not start with that value. A panel size not in the list, or no built-in panel (such as a clamshell Mac), is an info line and the mode is left alone. When the mode is listed, only the built-in display changes; other displays are left on their current mode. If `displayplacer` is missing or that mode is not listed, the manual step above is the fallback (System Settings → Displays).

Automatically adjust brightness stays by hand. It needs an admin password, and the saved value is a root-owned file. `bootstrap.sh` names this step before the checklist. The walk-through opens System Settings → Displays. True Tone and Slightly dim the display on battery are left alone.

Power (manual step `ac-sleep`) is in [Troubleshooting](troubleshooting.md#ac-idle-sleep): on mains power the Mac does not sleep on its own, the display sleeps after 10 minutes, and wake for network access is on; on battery the display sleeps after 2 minutes. Closing the lid still sleeps the Mac. Battery idle sleep is not changed. `--fix` does not run sudo.

Charge Limit (manual step `charge-limit`) is 80% on an Apple silicon laptop, from macOS Tahoe 26.4 on. It is not a row on the Battery page: click ⓘ next to Charging, drag Charge Limit to 80% (leave Optimised Battery Charging on), then Done. Apple documents no command that sets it: `pmset` has none, and the Shortcuts action Set Battery Charge Limit is not a shell command. `pmset -g` and `pmset -g custom` show sleep timers and the live battery. `pmset -g battlimit` calls the private `IOPSCopyBatteryLevelLimits` and needs the entitlement `com.apple.private.iokit.soc-limit`, which an unprivileged reader does not have. `ioreg -rn AppleSmartBattery` and `system_profiler SPPowerDataType` show the live charge, not the limit. The power preferences under `/Library/Preferences` and `~/Library` have no user-readable percentage for it. A desktop has no battery. The step stays by hand.

Edge Light (manual step `edge-light`) is Off. It lights the edges of the screen like a ring light during a video call. Start a video call, or open Photo Booth or FaceTime, so the camera is on. Then click Control Centre in the menu bar, click Video Effects, and click Edge Light so it is Off. On this Mac the on/off state is in `~/Library/Group Containers/group.com.apple.secure-control-center-preferences/Library/Preferences/group.com.apple.secure-control-center-preferences.av.plist`, and reading that file is permission denied. RingLightHelper's group (`group.com.apple.ringlight`) holds no preferences. Nothing writes either place. The step can't be checked, so it is always shown. `macconfig` lists it as `MANUAL:`, the same wording `manualsteps` uses.

Notification Centre is four settings at the top of System Settings → Notifications. Click Notifications in the sidebar, then Notification Center. Click the Show previews menu and choose When Unlocked. Turn off when display is sleeping. Turn on when screen is locked. Click the menu for when mirroring or sharing the display and choose Notifications Off. Those are manual steps `notifications-previews`, `notifications-display-sleep`, `notifications-lock-screen`, and `notifications-mirroring`. They are not the per-app Allow notifications bits. An app's own preview is a different control. The old preferences file `com.apple.ncprefs` is not the store on this macOS, and no key in the notification store has been shown to match these four. Nothing reads them and nothing writes them. `manualsteps` and `macconfig` label each one `MANUAL: Can't check this automatically. If it's already set, press s.`

The apps that must have notifications off are Calendar, FaceTime, Game Center, Home, Tips, Wallet, and Messages (manual step `notifications-apps`). For each one: System Settings → Notifications → the app → turn off Allow notifications. Messages may say Critical in the list. That means Allow notifications is off and Critical Alerts stay allowed, which is what we want. When one of those seven is still on, the reason line is `NOTSET:` and the check's detail. Leave Santa, SentinelAgent, and Kerberos as they are. The check never asks you to turn those off.

Control Centre (manual step `control-centre-controls`) keeps Screen Mirroring, Wi-Fi, Bluetooth, Now Playing, Display and Sound, and drops AirDrop, Stage Manager, Dark Mode, Screenshot and Focus. Click Control Centre in the menu bar, then Edit Controls. Click the minus on AirDrop, Stage Manager, Dark Mode, Screenshot and Focus, or drag each one out, then Done. Clicking Done is what saves it. The only readable layout file is `~/Library/Preferences/ByHost/com.apple.controlcenter.bentoboxes.<host UUID>.plist`. It keeps a history of module instances in an undocumented nested binary format, and it was not updated when the tiles were removed. On 25 Oct 2026 it still listed AirDrop and FocusModes hours after they were gone from Control Centre, so it can't tell whether a tile is showing. Nothing writes that file. The step stays by hand.

The desktop picture (Tahoe Night, Landscape) stays by hand. It is a system wallpaper-catalog asset, not a file under `/System/Library/Desktop Pictures`, so System Events cannot select it, and the wallpaper store is not written. A different picture is a warning. `--fix` does not change it. The account picture (the Dog) is checked from the picture on the user account. A different picture is a warning. `--fix` does not change it.

Finder sidebar Favorites are checked against `lib/sidebar-favorites.list` by reading the Finder sidebar file (Applications, Desktop, Developer, Documents, Downloads, Movies, Music, Pictures). `macconfig --fix` does not change them. macconfig also checks the Tags group collapsed, Recents and Shared hidden, and, when the sidebar files name the row, AirDrop and iCloud Drive hidden, and your home folder, Macintosh HD, Network, and Trash visible. No tags are shown in the sidebar: `FavoriteTagNames` in `com.apple.finder` is an empty list, which is every box under Finder → Settings → Tags → Show these tags in the sidebar unticked. A missing key means Finder is still showing its default tags. `ShowRecentTags` is not checked. Finder → Settings → Tags has no control that turns recent tags off, and those boxes only change `FavoriteTagNames`. A row the files do not name is reported as still by hand. `macconfig --fix` does not change the sidebar or the tag list.

Notes: Mouse-wheel direction (Natural) is set in Logi Options+, not System Settings: the macOS natural-scrolling switch is global and also flips the trackpad. The Logi Options+ values are checked automatically (see [Logi Options+](settings.md#logi-options)). The Finder, Logi Options+ and Raycast subsections in [Settings](settings.md) have the click-by-click detail.
EOF
}

write_out() {
  local tmp
  tmp="$(mktemp "${OUT}.tmp.XXXXXX")"
  # shellcheck disable=SC2064  # tmp is intentional: clean up this render, not a later one
  trap "rm -f '$tmp'" RETURN
  render > "$tmp"
  mv "$tmp" "$OUT"
  trap - RETURN
}

check_out() {
  local tmp
  if [ ! -f "$OUT" ]; then
    echo "docs/manual-steps.md is missing. Regenerate with scripts/render-manual-steps-doc.sh" >&2
    return 1
  fi
  tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" RETURN
  render > "$tmp"
  if cmp -s "$OUT" "$tmp"; then
    trap - RETURN
    rm -f "$tmp"
    return 0
  fi
  echo "docs/manual-steps.md is stale. Regenerate with scripts/render-manual-steps-doc.sh" >&2
  diff -u "$OUT" "$tmp" >&2 || true
  trap - RETURN
  rm -f "$tmp"
  return 1
}

main() {
  case "${1:-}" in
    -h|--help) usage ;;
    --stdout) render ;;
    --check) check_out ;;
    '') write_out ;;
    *) echo "Unknown option: $1 (try --help)" >&2; return 2 ;;
  esac
}

main "$@"
