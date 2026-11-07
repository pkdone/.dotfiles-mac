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

Some setup stays manual: privacy permissions (TCC / DriverKit), sign-ins, Fleet apps, full Xcode, and settings that aren't a single reliable `defaults` write (Notification Centre show previews, display sleeping, the lock screen, and mirroring, a Finder sidebar row the sidebar files do not name, mouse double-click and secondary click, the Control Centre tiles, Center Stage for Zoom, the battery charge limit, Google Meet Framing, and Automatically adjust brightness). The account picture, the desktop picture, the Finder sidebar rows the files do name, and Allow in the Menu Bar for the apps in `lib/menubar-allow.list` are checked and not changed. **`lib/manual-steps.list` is the single source of truth** for them; `scripts/manual-steps.sh` reads it. Per-app Allow Notifications is checked by `macconfig-check.sh` (see [Notifications](settings.md#notifications)). Allow in the Menu Bar is checked the same way (see [Settings](settings.md)). Built-in display More Space, and the ARZOPA portable monitor when it is plugged in, are set by `macos.sh` with `displayplacer` when that mode is listed ([Settings](settings.md#macos-defaults)). Automatically adjust brightness stays by hand under System Settings → Displays when it is on, or when the check can't read it. Spotlight → Results from Apps is checked by hand: the toggles are not in a preference the check can read, so nothing is written. Look up & data detectors is checked and not written. Trackpad tap to click, click pressure, secondary click, three-finger drag, tracking speed, Force Click, and the gesture keys are applied by `macos.sh` (see [macOS defaults](settings.md#macos-defaults)).

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

A step whose check is `@macconfig:<area>` uses the same read-only check as that section of `macconfig-check.sh` (Focus modes, Focus Shortcuts, notifications, Allow in the Menu Bar, and the others listed in `lib/manual-steps.list`). `manualsteps check` and `manualsteps open` report that result, so a Focus mode that is not created yet shows up as not set. When `macconfig` itself is running, that section has already reported the step. Manual steps still prints one line in the same numbered place, for example `ok    1. Install the company apps… — checked above under MDM / company apps`. The word in front is that section's ok, warn, or fail when the section recorded one, and `info` when it did not, so a section that did not run is not called ok. The line names the section heading (`Allow in the Menu Bar` for `@macconfig:menubar`). It is not added to the summary totals, and it does not say to press s. Placed widgets (`remove-widgets`) are the same line for the Desktop widgets section.

`check` never writes a setting or prompts, and wraps every slow call in a timeout. It verifies what it can reliably read: privacy grants from the system TCC database (needs Full Disk Access for the terminal or agent running it, otherwise those become "by hand"), pointer size, Accessibility trackpad dragging (`Dragging=1`, `DragLock=0`), Look up & data detectors (`com.apple.trackpad.forceClick` = 0), mouse tracking speed `1.5` (7th notch from Slow) and scrolling speed `0.5` (5th notch from Slow) (check only; `defaults write` does not reliably drive System Settings → Mouse), the Karabiner driver, the Hammerspoon grant (live via `hs`), installed apps, Logi Options+ values (from a temp copy of its settings database), `gh auth status`, and the 1Password CLI (`op whoami`, otherwise a count of accounts from `op account list`). Spotlight → Results from Apps is reported as check by hand. Edge Light is reported as check by hand too: the on/off state cannot be read, so the step is always shown. Steps marked `macconfig-check.sh` below are verified by their own `macconfig-check.sh` section. To add a step, add a row to `lib/manual-steps.list` (format in its header) and regenerate this file with `scripts/render-manual-steps-doc.sh` (the table is `scripts/manual-steps.sh list --markdown`).

British input (`com.apple.HIToolbox` `AppleEnabledInputSources` and `AppleSelectedInputSources`, the keyboard layout name must be British only; Press and Hold and similar non-layout entries are fine; step `input-british`), pointer size (step `pointer-size`), `gh auth status` (step `gh-auth`), and the 1Password CLI (step `1password-cli`) are those same `scripts/manual-steps.sh` checks. `macconfig-check.sh` prints them in the Manual steps section and does not run them a second time. A miss is a warning tagged with the step id (Needs Paul), the same way as `mouse-settings`. `--fix` does not change them. There is no sudo, and the notification store is not written. `op whoami` succeeding means this terminal is signed in. If it fails, `op account list --format=json` is piped into a counter inside the timeout. Only the number of accounts is kept: the body is not stored in a shell variable, a log, or a temp file. One or more accounts means the integration is set up (a new terminal asks to unlock on first use), so the step is not shown. No account is a warning. The check never runs `op signin`, never prompts, and never prints account ids, emails, UUIDs, or URLs.

EOF
  "$MS" list --markdown
  cat <<'EOF'

`NOTSET:` means the check found the setting missing or wrong. `MANUAL:` means the step can't be checked. Both are explained above.

Each note lives with the setting:

- Trackpad, mouse, dragging, and Look up & data detectors: [macOS defaults](settings.md#macos-defaults).
- Desktop widgets and Stage Manager: [macOS defaults](settings.md#macos-defaults). `manualsteps open` shows `remove-widgets` only when a widget is still placed. `macconfig --fix` does not write that plist.
- Built-in display More Space and the ARZOPA monitor: [macOS defaults](settings.md#macos-defaults).
- Automatically adjust brightness: [macOS defaults](settings.md#macos-defaults).
- Power (manual step `ac-sleep`): [Troubleshooting](troubleshooting.md#ac-idle-sleep).
- Charge limit (manual step `charge-limit`), Edge Light (manual step `edge-light`), Center Stage (manual step `zoom-center-stage`), and Google Meet Framing (manual step `meet-framing`): [By hand](settings.md#by-hand).
- Notification Centre and the seven apps: [Notifications](settings.md#notifications).
- Allow in the Menu Bar and Control Centre (manual step `control-centre-controls`): [macOS defaults](settings.md#macos-defaults).
- Wallpaper, the account picture, and the Finder sidebar: [macOS defaults](settings.md#macos-defaults) and [Finder](settings.md#finder).
- Logi Options+ and the wheel direction: [Logi Options+](settings.md#logi-options).
- Raycast: [Raycast](settings.md#raycast).
- Focus modes and Shortcuts: [Modes](modes.md).
- Full Xcode (manual steps `xcode-app`, `xcode-select`, `xcode-license`, `xcode-first-launch`): [Xcode](settings.md#xcode). Command Line Tools are not full Xcode. The Mac App Store install, `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, `sudo xcodebuild -license accept`, and first launch (`sudo xcodebuild -runFirstLaunch`, or opening Xcode once) need an administrator or the Xcode window. `bootstrap.sh` and `macconfig --fix` do not run them.
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
