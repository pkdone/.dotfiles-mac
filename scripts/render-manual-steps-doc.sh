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

Some setup stays manual: privacy permissions (TCC / DriverKit), sign-ins, company MDM apps, and settings that aren't a single reliable `defaults` key (notification mirroring, Spotlight, mouse double-click and secondary click, Look up & data detectors, Accessibility trackpad dragging, and the Menu Bar allow-list for Raycast, Logi Options+ and Docker). **`lib/manual-steps.list` is the single source of truth** for them; `scripts/manual-steps.sh` reads it. Per-app Allow Notifications is checked by `macconfig-check.sh` (see [Notifications](settings.md#notifications)). Built-in display More Space is checked from `system_profiler` (see below). Trackpad tap to click, click pressure, secondary click, three-finger drag, tracking speed, and Force Click are applied by `macos.sh` (see [macOS defaults](settings.md#macos-defaults)).

This file is generated from `lib/manual-steps.list`. Edit the list, then run `scripts/render-manual-steps-doc.sh`.

```bash
~/.dotfiles-mac/scripts/manual-steps.sh list    # numbered checklist
~/.dotfiles-mac/scripts/manual-steps.sh open    # walk through the steps not yet done, opening each System Settings page (terminal only; --all for every step)
~/.dotfiles-mac/scripts/manual-steps.sh check   # read-only: ok / warn / by hand (also the "Manual steps" section of macconfig-check.sh)
```

`check` never writes a setting or prompts, and wraps every slow call in a timeout. It verifies what it can reliably read: privacy grants from the system TCC database (needs Full Disk Access for the terminal or agent running it, otherwise those become "by hand"), pointer size, Accessibility trackpad dragging (`Dragging=1`, `DragLock=0`), mouse tracking speed `1.5` and scrolling speed `0.5` (check only; `defaults write` does not reliably drive System Settings → Mouse), the Karabiner driver, the Hammerspoon grant (live via `hs`), installed apps, Logi Options+ values (from a temp copy of its settings database), `gh auth status` and `op whoami`. Steps marked `macconfig-check.sh` below are verified by their own `macconfig-check.sh` section. To add a step, add a row to `lib/manual-steps.list` (format in its header) and regenerate this file with `scripts/render-manual-steps-doc.sh` (the table is `scripts/manual-steps.sh list --markdown`).

EOF
  "$MS" list --markdown
  cat <<'EOF'

Trackpad tap to click, click pressure Light, secondary click in the bottom right corner, three-finger drag Off, tracking speed `0.6875`, and Force Click and haptic feedback On are in `lib/macos-defaults.list` (`macos.sh` / `macconfig-check.sh`; `macconfig --fix` repairs them). A change may need a logout/login before the trackpad follows it. Look up & data detectors stays in the table above: `ActuateDetents` and `ForceSuppressed` only cover Force Click and haptic feedback, both On. Use trackpad for dragging stays a check (`Dragging=1`, `DragLock=0`: On, without drag lock) because that Accessibility setting does not reliably follow `defaults write`.

Mouse tracking speed (`NSGlobalDomain` `com.apple.mouse.scaling` = `1.5`) and scrolling speed (`com.apple.scrollwheel.scaling` = `0.5`) are the same kind of check. `macconfig-check.sh` warns when they drift (`mouse-settings` in `lib/autofix.list`, Needs Paul). `--fix` does not write them: on recent macOS those System Settings → Mouse sliders do not reliably follow `defaults write`. Double-click speed and secondary click on the right side stay in that step. The double-click threshold key is unset on this Mac, so it cannot be checked. Wheel direction (Natural) stays in Logi Options+.

Desktop widgets and Stage Manager are in `lib/macos-defaults.list` too (`StandardHideWidgets` and `StageManagerHideWidgets` = true, `GloballyEnabled` = false). `macos.sh` applies them and `macconfig --fix` repairs them. `restart` is empty, so a repair restarts no process. Click wallpaper to reveal desktop is not pinned.

Built-in display **More Space** is checked by the **Display (More Space)** section of `macconfig-check.sh`. The expected prefix is `lib/display-resolution.list` (`1800 x 1169` on this Color LCD). The check reads `system_profiler SPDisplaysDataType -json` and warns when the built-in panel's `_spdisplays_resolution` does not start with that prefix (`1800 x 1169 @ 120.00Hz` is More Space on this panel). No built-in panel, such as a clamshell Mac, is an info line. `--fix` does not change the display mode.

AC idle sleep on mains power (`sudo pmset -c sleep 0`, manual step `ac-sleep`) is in [Troubleshooting](troubleshooting.md#ac-idle-sleep).

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
