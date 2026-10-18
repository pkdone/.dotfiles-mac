#!/usr/bin/env python3
"""Read-only check of per-app Allow Notifications.

macOS 27 stores per-app notification settings in the binary plist

    ~/Library/Group Containers/group.com.apple.usernoted/Library/Preferences/group.com.apple.usernoted.plist

`~/Library/Preferences/com.apple.ncprefs.plist` is not used. Top-level keys
include `apps` (an array of dicts with `bundle-id`, `flags`, `auth`, `path`,
`grouping`). This reads that file with plistlib and never writes it, never
calls `defaults`, and never restarts `usernoted`. There is no --fix.

Allow Notifications is one bit of `flags`. The constant below is the whole
decoder: change it if a macOS update moves the bit.

    ALLOW_NOTIFICATIONS_BIT = 25    # 1 << 25, set = allowed (not inverted)

Sources for bit 25, set = on:

- Hush (macOS 26, this same usernoted plist): NotificationFlags.allowNotifications,
  bitPosition 25, isInverted false.
  https://github.com/Tembeon/hush
- ncmanager (older com.apple.ncprefs): allow_notifications = 1 << 25.

macOS 27 samples from this Mac agree. Bit 25 is clear on every app in
lib/notifications-off.list (Slack, Spotify, Teams and Cursor Nightly share
276832270; Calendar 814219286; FaceTime 278929416; Game Center 5109194758;
Home 830996486; Mail 276824078; Tips 294125584; Wallet 814219270) and set on
Chrome (com.google.Chrome, 41951246). Hammerspoon (8396822) is clear too; it
is reviewed, not required off.

To recalibrate: toggle Allow Notifications for one app in System Settings,
read that app's flags again, and set ALLOW_NOTIFICATIONS_BIT to the bit that
flipped. Other bits (not decoded here) from the same Hush table: 0 Notification
Center off, 1 badge, 2 sound, 3 banners, 4 alerts, 12 Lock Screen off,
29 Time Sensitive, 34 Summarize off.

Output, one line per result, fields separated by `|`:

    ok|bundle-id|message       listed app, Allow Notifications is off
    warn|bundle-id|message     listed app, allowed / missing / flags unreadable
    info|bundle-id|message     third-party app in neither list
    error|-|message            store or list missing, or the plist did not parse

`com.apple.*` and `_SYSTEM_CENTER_*` are ignored unless listed in the Off
file. Exit status is 0 whenever a line was printed, including warnings, so a
bad plist cannot crash macconfig-check.sh.
"""
from __future__ import annotations

import argparse
import os
import plistlib
import re
import sys

# Set means System Settings → Notifications → Allow Notifications is on.
# Not inverted. Recalibrate this and only this if the bit moves.
ALLOW_NOTIFICATIONS_BIT = 25

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PLIST = os.path.expanduser(
    "~/Library/Group Containers/group.com.apple.usernoted/Library/Preferences/"
    "group.com.apple.usernoted.plist"
)
DEFAULT_OFF = os.path.join(HERE, "notifications-off.list")
DEFAULT_REVIEWED = os.path.join(HERE, "notifications-reviewed.list")
BUNDLE_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*$")


def emit(status: str, bundle: str, message: str) -> None:
    text = str(message).replace("\n", " ").replace("|", "/")
    ident = bundle or "-"
    ident = ident.replace("|", "/").replace("\n", " ")
    print(f"{status}|{ident}|{text}")


def is_ignored_bundle(bundle: str) -> bool:
    return bundle.startswith("com.apple.") or bundle.startswith("_SYSTEM_CENTER_")


def load_list(path: str) -> list[tuple[str, str]]:
    """Bundle ids in file order. Text after # is the display name."""
    rows: list[tuple[str, str]] = []
    seen: set[str] = set()
    with open(path, encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            body, _, comment = raw.partition("#")
            bundle = body.strip()
            label = comment.strip() or bundle
            if not bundle:
                continue
            if len(bundle.split()) != 1 or not BUNDLE_RE.match(bundle):
                name = os.path.basename(path)
                raise ValueError(f"{name}:{lineno}: expected one bundle id")
            if bundle in seen:
                name = os.path.basename(path)
                raise ValueError(f"{name}:{lineno}: duplicate bundle id {bundle}")
            seen.add(bundle)
            rows.append((bundle, label))
    return rows


def allow_bit_set(flags: object) -> bool | None:
    if isinstance(flags, bool) or not isinstance(flags, int):
        return None
    return ((flags >> ALLOW_NOTIFICATIONS_BIT) & 1) == 1


def allowed_state(flag_values: list[object]) -> str:
    """'on' if any copy has the bit set, 'off' if a copy was readable, else 'unreadable'."""
    states = [allow_bit_set(value) for value in flag_values]
    if any(state is True for state in states):
        return "on"
    if any(state is False for state in states):
        return "off"
    return "unreadable"


def format_flags(flag_values: list[object]) -> str:
    parts: list[str] = []
    for value in flag_values:
        if isinstance(value, bool) or not isinstance(value, int):
            parts.append("?")
        else:
            parts.append(str(value))
    return "/".join(parts) if parts else "?"


def index_apps(apps: list[object]) -> tuple[dict[str, list[object]], list[str]]:
    found: dict[str, list[object]] = {}
    order: list[str] = []
    for item in apps:
        if not isinstance(item, dict):
            continue
        bundle = item.get("bundle-id")
        if not isinstance(bundle, str) or not bundle:
            continue
        if bundle not in found:
            found[bundle] = []
            order.append(bundle)
        found[bundle].append(item.get("flags"))
    return found, order


def report(
    off: list[tuple[str, str]],
    reviewed: list[tuple[str, str]],
    found: dict[str, list[object]],
    order: list[str],
) -> None:
    off_ids = {bundle for bundle, _label in off}
    reviewed_ids = {bundle for bundle, _label in reviewed}
    for bundle, label in off:
        flags = found.get(bundle)
        if flags is None:
            emit(
                "warn",
                bundle,
                f"{label} ({bundle}): not in the notification store"
                " — can't confirm Allow Notifications is off",
            )
            continue
        state = allowed_state(flags)
        shown = format_flags(flags)
        if state == "on":
            emit(
                "warn",
                bundle,
                f"{label} ({bundle}): Allow Notifications is on"
                f" (flags={shown}, bit {ALLOW_NOTIFICATIONS_BIT} set)"
                " — System Settings → Notifications → turn it off."
                " macconfig-check.sh --fix does not change this",
            )
        elif state == "off":
            emit(
                "ok",
                bundle,
                f"{label} ({bundle}): Allow Notifications is off (flags={shown})",
            )
        else:
            emit(
                "warn",
                bundle,
                f"{label} ({bundle}): flags unreadable ({shown})"
                " — can't confirm Allow Notifications is off",
            )
    for bundle in order:
        if is_ignored_bundle(bundle) or bundle in off_ids or bundle in reviewed_ids:
            continue
        flags = found[bundle]
        state = allowed_state(flags)
        shown = format_flags(flags)
        if state == "on":
            detail = (
                f"Allow Notifications is on (flags={shown},"
                f" bit {ALLOW_NOTIFICATIONS_BIT} set)"
            )
        elif state == "off":
            detail = f"Allow Notifications is off (flags={shown})"
        else:
            detail = f"flags unreadable ({shown})"
        emit(
            "info",
            bundle,
            f"{bundle}: third-party app is not in lib/notifications-reviewed.list"
            f" or lib/notifications-off.list ({detail})"
            " — review it in System Settings → Notifications, then add the"
            " bundle id to one of those lists",
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="notification-prefs.py", description=__doc__)
    parser.add_argument("--plist", default=DEFAULT_PLIST, help="usernoted plist to read")
    parser.add_argument("--off", default=DEFAULT_OFF, help="bundle ids that must be off")
    parser.add_argument(
        "--reviewed", default=DEFAULT_REVIEWED, help="third-party bundle ids already reviewed"
    )
    args = parser.parse_args(argv)
    try:
        off = load_list(args.off)
        reviewed = load_list(args.reviewed)
    except FileNotFoundError as exc:
        emit("error", "-", f"notification list missing ({exc.filename})")
        return 0
    except Exception as exc:  # noqa: BLE001 - report, don't crash macconfig-check.sh
        emit("error", "-", f"could not read notification lists ({exc})")
        return 0
    if not off:
        emit("error", "-", "notifications-off list has no bundle ids")
        return 0
    try:
        with open(args.plist, "rb") as fh:
            data = fh.read()
        prefs = plistlib.loads(data)
    except FileNotFoundError:
        emit(
            "error",
            "-",
            f"notification store missing at {args.plist}"
            " — can't check Allow Notifications",
        )
        return 0
    except PermissionError:
        emit(
            "error",
            "-",
            "notification store unreadable (Full Disk Access)"
            " — System Settings → Privacy & Security → Full Disk Access",
        )
        return 0
    except Exception as exc:  # noqa: BLE001 - a torn or foreign plist is a warning
        emit("error", "-", f"could not read the notification store ({exc})")
        return 0
    if not isinstance(prefs, dict):
        emit("error", "-", "notification store root is not a dictionary")
        return 0
    apps = prefs.get("apps")
    if not isinstance(apps, list):
        emit("error", "-", "notification store has no apps array")
        return 0
    found, order = index_apps(apps)
    report(off, reviewed, found, order)
    return 0


if __name__ == "__main__":
    sys.exit(main())
