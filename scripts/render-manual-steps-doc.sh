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

> _Manual — no script can do these. `install.sh` and `bootstrap.sh` print this checklist when they finish and, on a terminal, offer to walk through it._

Some setup stays manual: privacy permissions (TCC / DriverKit), sign-ins, company MDM apps, and settings that aren't a single reliable `defaults` write (notification mirroring, a Finder sidebar row the sidebar files do not name, mouse double-click and secondary click, the Menu Bar allow-list for Raycast, Logi Options+ and Docker, and the battery charge limit). The account picture, the desktop picture, and the Finder sidebar rows the files do name are checked and not changed. **`lib/manual-steps.list` is the single source of truth** for them; `scripts/manual-steps.sh` reads it. Per-app Allow Notifications is checked by `macconfig-check.sh` (see [Notifications](settings.md#notifications)). Built-in display More Space is checked from `system_profiler` (see below). Spotlight → Results from Apps is check by hand: the toggles are not in a preference the check can read, so nothing is written. Look up & data detectors and the App Store sign-in are checked and not written. Trackpad tap to click, click pressure, secondary click, three-finger drag, tracking speed, Force Click, and the gesture keys are applied by `macos.sh` (see [macOS defaults](settings.md#macos-defaults)).

This file is generated from `lib/manual-steps.list`. Edit the list, then run `scripts/render-manual-steps-doc.sh`.

`manualsteps` is the fish function for `scripts/manual-steps.sh`, installed with the others in `fish/functions/`. With no arguments it runs `check`. Any arguments pass through (`manualsteps list`, `manualsteps open`, `manualsteps open --all`, `manualsteps check`, `manualsteps --help`), and the exit status is the script's.

```bash
manualsteps          # check (no arguments): ok / warn / by hand (also the "Manual steps" section of macconfig-check.sh)
manualsteps open     # walk through the steps not yet done, opening each System Settings page (terminal only; --all for every step)
manualsteps list     # numbered checklist
~/.dotfiles-mac/scripts/manual-steps.sh list    # numbered checklist (same as manualsteps list)
~/.dotfiles-mac/scripts/manual-steps.sh open    # walk through the steps not yet done, opening each System Settings page (terminal only; --all for every step)
~/.dotfiles-mac/scripts/manual-steps.sh check   # read-only: ok / warn / by hand (same as manualsteps)
```

`check` never writes a setting or prompts, and wraps every slow call in a timeout. It verifies what it can reliably read: privacy grants from the system TCC database (needs Full Disk Access for the terminal or agent running it, otherwise those become "by hand"), pointer size, Accessibility trackpad dragging (`Dragging=1`, `DragLock=0`), Look up & data detectors (`com.apple.trackpad.forceClick` = 0), mouse tracking speed `1.5` and scrolling speed `0.5` (check only; `defaults write` does not reliably drive System Settings → Mouse), the Karabiner driver, the Hammerspoon grant (live via `hs`), installed apps, Logi Options+ values (from a temp copy of its settings database), `gh auth status`, `op whoami`, and `mas list`. Spotlight → Results from Apps is reported as check by hand. Steps marked `macconfig-check.sh` below are verified by their own `macconfig-check.sh` section. To add a step, add a row to `lib/manual-steps.list` (format in its header) and regenerate this file with `scripts/render-manual-steps-doc.sh` (the table is `scripts/manual-steps.sh list --markdown`).

British input (`com.apple.HIToolbox` `AppleSelectedInputSources`, the keyboard layout must be British only; Press and Hold and similar non-layout entries are fine; step `input-british`), pointer size (step `pointer-size`), `gh auth status` (step `gh-auth`), `op whoami` (step `1password-cli`), and `mas list` (step `app-store`) are those same `scripts/manual-steps.sh` checks. `macconfig-check.sh` prints them in the Manual steps section and does not run them a second time. A miss is a warning tagged with the step id (Needs Paul), the same way as `mouse-settings`. `--fix` does not change them. There is no sudo, and the notification store is not written. `op whoami` failing because 1Password is installed but locked or not signed in is info, not a warning.

EOF
  "$MS" list --markdown
  cat <<'EOF'

Trackpad tap to click, click pressure Light, secondary click in the bottom right corner, three-finger drag Off, tracking speed `0.6875`, Force Click and haptic feedback On, natural scrolling, and the 3/4/5-finger gestures are in `lib/macos-defaults.list` (`macos.sh` / `macconfig-check.sh`; `macconfig --fix` repairs them). The same values are written for the built-in trackpad and the Bluetooth trackpad. A change may need a logout/login before the trackpad follows it. Look up & data detectors is the check in the table above (`com.apple.trackpad.forceClick` = 0). `ActuateDetents` and `ForceSuppressed` only cover Force Click and haptic feedback, both On. Use trackpad for dragging stays a check (`Dragging=1`, `DragLock=0`: On, without drag lock) because that Accessibility setting does not reliably follow `defaults write`.

Mouse tracking speed (`NSGlobalDomain` `com.apple.mouse.scaling` = `1.5`) and scrolling speed (`com.apple.scrollwheel.scaling` = `0.5`) are the same kind of check. `macconfig-check.sh` warns when they drift (`mouse-settings` in `lib/autofix.list`, Needs Paul). `--fix` does not write them: on recent macOS those System Settings → Mouse sliders do not reliably follow `defaults write`. Double-click speed and secondary click on the right side stay in that step. The double-click threshold key is unset on this Mac, so it cannot be checked. Wheel direction (Natural) stays in Logi Options+.

Desktop widgets and Stage Manager are in `lib/macos-defaults.list` too (`StandardHideWidgets` and `StageManagerHideWidgets` = true, `GloballyEnabled` = false). `macos.sh` applies them and `macconfig --fix` repairs them. `restart` is empty, so a repair restarts no process. Click wallpaper to reveal desktop is not pinned.

Built-in display **More Space** is checked by the **Display (More Space)** section of `macconfig-check.sh`. The check reads `system_profiler SPDisplaysDataType -json`, finds the built-in panel's size, and looks up its More Space value in `lib/display-resolution.list`: `1800 x 1169` for the 14" panel (3024x1964) and `2056 x 1329` for the 16" panel (3456x2234). It warns when `_spdisplays_resolution` does not start with that value. A panel size not in the list, or no built-in panel (such as a clamshell Mac), is an info line. `--fix` does not change the display mode.

Power (manual step `ac-sleep`) is in [Troubleshooting](troubleshooting.md#ac-idle-sleep): on mains power the Mac does not sleep on its own, the display sleeps after 10 minutes, and wake for network access is on; on battery the display sleeps after 2 minutes. Closing the lid still sleeps the Mac. Battery idle sleep is not changed. `--fix` does not run sudo.

Charge Limit (manual step `charge-limit`) is 80% on an Apple silicon laptop, from macOS Tahoe 26.4 on. Apple documents no command that sets it: `pmset` has none, and the Shortcuts action Set Battery Charge Limit is not a shell command. `pmset -g` and `pmset -g custom` show sleep timers and the live battery. `pmset -g battlimit` calls the private `IOPSCopyBatteryLevelLimits` and needs the entitlement `com.apple.private.iokit.soc-limit`, which an unprivileged reader does not have. `ioreg -rn AppleSmartBattery` and `system_profiler SPPowerDataType` show the live charge, not the limit. The power preferences under `/Library/Preferences` and `~/Library` have no user-readable percentage for it. A desktop has no battery. The step stays by hand.

The desktop picture (Tahoe Night, Landscape) is checked from the wallpaper store. A different picture is a warning. `--fix` does not change it. The account picture (the Dog) is checked from the picture on the user account. A different picture is a warning. `--fix` does not change it.

Finder sidebar Favorites are checked against `lib/sidebar-favorites.list` by reading the Finder sidebar file. `macconfig --fix` does not change them. macconfig also checks the Tags group collapsed, Recents hidden, and, when the sidebar files name the row, Shared at the top, AirDrop and iCloud Drive hidden, and your home folder, Macintosh HD, Network, and Trash visible. A row the files do not name is reported as still by hand. `macconfig --fix` does not change the sidebar.

Notes: Passwords in iCloud = iCloud Keychain, so don't turn it Off casually. Mouse-wheel direction (Natural) is set in Logi Options+, not System Settings: the macOS natural-scrolling switch is global and also flips the trackpad. The Logi Options+ values are checked automatically (see [Logi Options+](settings.md#logi-options)). The Finder, Logi Options+, Gemini and Raycast subsections in [Settings](settings.md) have the click-by-click detail.
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
