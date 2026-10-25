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

Alert style is two other bits of the same integer. Hammerspoon
(org.hammerspoon.Hammerspoon) must be Alerts so the DeepWork end-of-session
buttons show. This reports that style and never writes the store.

    ALERT_STYLE_BIT = 4             # 1 << 4 set, bit 3 clear = Alerts

Sources for bit 25, set = on:

- Hush (macOS 26, this same usernoted plist): NotificationFlags.allowNotifications,
  bitPosition 25, isInverted false.
  https://github.com/Tembeon/hush
- ncmanager (older com.apple.ncprefs): allow_notifications = 1 << 25.

macOS 27 samples from this Mac agree that bit 25 set matches a row System
Settings is showing as on. Chrome (com.google.Chrome, 41951246) has it set.
A later read of apps that showed as on was flags=310386702, which is the
older Slack sample 276832270 plus exactly bit 25.

Bit 25 clear is not proof the System Settings row is off. On pdone-mac2,
io.tailscale.ipn.macsys and com.logi.cp-dev-mgr were both flags=268443662.
That value is badge (bit 1), sound (bit 2), and banner (bit 3, the Desktop
subtitle), plus bits 13 and 28. Bit 25 is clear. System Settings still
showed Tailscale on (Badges, Sounds, Desktop). Logi Options+ had the same
flags and was not described as on, so those bits are not themselves "on".
The Tailscale row in System Settings may be a different bundle id
(io.tailscale.ipn.macos, or a network-extension id) from the one that was
read. Either way, a clear bit 25 must not be reported as "Allow
Notifications is off".

Messages (com.apple.MobileSMS) is on the Off list. System Settings shows
"Critical" when normal notifications are off and Critical Alerts stay
allowed. Bit 25 clear, with any other bit set, is the same uncertain clear
result, not a warning. The Off list is only those seven apps. Hammerspoon
(8396822) is clear on bit 25 too; it is reviewed, not required off.

To recalibrate: toggle Allow Notifications for one app in System Settings,
read that app's flags again, and set ALLOW_NOTIFICATIONS_BIT to the bit that
flipped. Other bits from the same Hush table: 0 Notification Center off,
1 badge, 2 sound, 12 Lock Screen off, 29 Time Sensitive, 34 Summarize off.

Alert style (Hush AlertStyle, this same usernoted plist; ncmanager's older
ncprefs store uses the same two bits):

    bit 3 (1 << 3) set, bit 4 clear = Banners   Hush alertTemporary
    bit 4 (1 << 4) set, bit 3 clear = Alerts    Hush alertPersistent
    both clear, or both set         = None      Hush treats both-set as Off

ncmanager names them style_banners = 1 << 3 and style_alerts = 1 << 4.
https://github.com/Tembeon/hush/blob/master/Hush/Models/AlertStyle.swift
https://github.com/Tembeon/hush/blob/master/Hush/Models/NotificationFlags.swift
https://github.com/bilousoleksandr/ncmanager

On this Mac, Hammerspoon flags 8396822 have bit 4 set and bit 3 clear (Alerts).
To recalibrate ALERT_STYLE_BIT: set Hammerspoon to Banners, then back to
Alerts, and set the constant to the bit that is set only for Alerts. Keep
BANNER_STYLE_BIT on the other one. Then run ./tests/notification-prefs.test.sh.

Output, one line per result, fields separated by `|`:

    ok|bundle-id|message       listed app, bit 25 is clear (not confirmed off)
    warn|bundle-id|message     listed app, bit 25 set, or flags unreadable
    info|bundle-id|message     listed app not in the store yet, or a third-party
                            app in neither list
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

# Alert style. Alerts means ALERT_STYLE_BIT is set and BANNER_STYLE_BIT is clear.
# Not inverted. Recalibrate these two if a macOS update moves the style bits
# (see the module docstring). On this Mac, Hammerspoon flags 8396822 are Alerts.
ALERT_STYLE_BIT = 4
BANNER_STYLE_BIT = 3
HAMMERSPOON_BUNDLE = "org.hammerspoon.Hammerspoon"

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


def alert_style(flags: object) -> str | None:
    """'Alerts', 'Banners', 'None', or None when flags are not an integer."""
    if isinstance(flags, bool) or not isinstance(flags, int):
        return None
    alerts = ((flags >> ALERT_STYLE_BIT) & 1) == 1
    banners = ((flags >> BANNER_STYLE_BIT) & 1) == 1
    if alerts and not banners:
        return "Alerts"
    if banners and not alerts:
        return "Banners"
    return "None"


def allow_bit_set(flags: object) -> bool | None:
    """True when bit 25 is set.

    Bit 25 set matched rows System Settings showed as on (flags=310386702).
    Bit 25 clear is not the opposite: io.tailscale.ipn.macsys flags=268443662
    has the bit clear and System Settings still showed Tailscale on. Other
    bits, including Critical Alerts, are not a separate drift.
    """
    if isinstance(flags, bool) or not isinstance(flags, int):
        return None
    return ((flags >> ALLOW_NOTIFICATIONS_BIT) & 1) == 1


def bit_clear_note(shown: str) -> str:
    """Say what was read. Do not claim the System Settings row is off."""
    return (
        f"flags={shown}, bit {ALLOW_NOTIFICATIONS_BIT} clear,"
        " not confirmed off in System Settings"
    )


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
                "info",
                bundle,
                f"{label} ({bundle}): not registered for notifications yet,"
                " nothing to turn off",
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
                f"{label} ({bundle}): {bit_clear_note(shown)}",
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
            detail = bit_clear_note(shown)
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
    report_hammerspoon_style(found)


def report_hammerspoon_style(found: dict[str, list[object]]) -> None:
    """Warn unless every readable Hammerspoon flags copy is Alerts."""
    flags = found.get(HAMMERSPOON_BUNDLE)
    where = (
        " System Settings → Notifications → Hammerspoon → Alerts."
        " macconfig-check.sh --fix does not change this"
    )
    if flags is None:
        emit(
            "info",
            HAMMERSPOON_BUNDLE,
            f"Hammerspoon ({HAMMERSPOON_BUNDLE}): not registered for"
            " notifications yet, so the Alerts style can't be checked until"
            " Hammerspoon has posted a notification",
        )
        return
    styles = [alert_style(value) for value in flags]
    shown = format_flags(flags)
    readable = [style for style in styles if style is not None]
    if readable and all(style == "Alerts" for style in readable):
        emit(
            "ok",
            HAMMERSPOON_BUNDLE,
            f"Hammerspoon ({HAMMERSPOON_BUNDLE}): notification style is Alerts"
            f" (flags={shown}, bit {ALERT_STYLE_BIT} set, bit {BANNER_STYLE_BIT} clear)",
        )
        return
    if not readable:
        emit(
            "warn",
            HAMMERSPOON_BUNDLE,
            f"Hammerspoon ({HAMMERSPOON_BUNDLE}): flags unreadable ({shown})"
            " — can't confirm notification style is Alerts."
            + where,
        )
        return
    named = "/".join(style if style is not None else "?" for style in styles)
    emit(
        "warn",
        HAMMERSPOON_BUNDLE,
        f"Hammerspoon ({HAMMERSPOON_BUNDLE}): notification style is {named}"
        f" (flags={shown}, bit {ALERT_STYLE_BIT} is Alerts when bit {BANNER_STYLE_BIT}"
        " is clear) — want Alerts."
        + where,
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
