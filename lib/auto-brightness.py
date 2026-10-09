#!/usr/bin/env python3
"""Read-only check of System Settings → Displays → Automatically adjust brightness.

`/usr/libexec/corebrightnessdiag status-info` prints a plist with no sudo.
This walks it for two keys and ignores everything else (True Tone, keyboard
brightness, battery dim):

    CBAutoBrightnessEnabled   bool, on when true
    DisplayBrightnessAuto     number, on when not 0

One line, fields separated by `|`:

    ok||message
    bad||message
    warn||message

Off means every copy of those keys is off. One display still on is drift.
A plist with neither key is a warning, not a pass.

Nothing here writes. The saved value lives in the root-owned CoreBrightness
plist; `--fix` does not change it.
"""
from __future__ import annotations

import argparse
import plistlib
import sys

KEYS = ("CBAutoBrightnessEnabled", "DisplayBrightnessAuto")


def emit(status: str, message: str) -> None:
    text = str(message).replace("\n", " ").replace("|", "/")
    print(f"{status}||{text}")


def load_plist(data: bytes):
    start = data.find(b"<?xml")
    if start < 0:
        start = data.find(b"<plist")
    if start >= 0:
        end = data.rfind(b"</plist>")
        if end >= 0:
            data = data[start:end + len(b"</plist>")]
    return plistlib.loads(data)


def is_on(value) -> bool | None:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value != 0
    if isinstance(value, str):
        word = value.strip().lower()
        if word in ("1", "true", "yes"):
            return True
        if word in ("0", "false", "no"):
            return False
    return None


def show(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def collect(node, found: list[tuple[str, object]]) -> None:
    if isinstance(node, dict):
        for key, value in node.items():
            if key in KEYS and not isinstance(value, (dict, list)):
                found.append((key, value))
            else:
                collect(value, found)
    elif isinstance(node, list):
        for item in node:
            collect(item, found)


def describe(found: list[tuple[str, object]]) -> str:
    parts = []
    for key in KEYS:
        vals = [show(value) for name, value in found if name == key]
        if vals:
            parts.append(f"{key}={'/'.join(vals)}")
    return ", ".join(parts)


def judge(found: list[tuple[str, object]]) -> tuple[str, str]:
    if not found:
        return (
            "warn",
            "status-info has no CBAutoBrightnessEnabled or DisplayBrightnessAuto"
            " — can't tell if Automatically adjust brightness is on",
        )
    unknown = [name for name, value in found if is_on(value) is None]
    if unknown:
        return ("warn", f"unreadable auto-brightness value for {', '.join(unknown)}")
    detail = describe(found)
    if any(is_on(value) for _name, value in found):
        return (
            "bad",
            "Automatically adjust brightness is on"
            f" ({detail}) — System Settings → Displays → turn it off."
            " macconfig-check.sh --fix does not change this (the CoreBrightness plist is"
            " root-owned; True Tone and Slightly dim the display on battery"
            " are left alone)",
        )
    return ("ok", f"Automatically adjust brightness is off ({detail})")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="auto-brightness.py", description=__doc__)
    parser.add_argument("--plist", default="", help="read this plist instead of stdin")
    args = parser.parse_args(argv)
    try:
        if args.plist:
            with open(args.plist, "rb") as fh:
                data = fh.read()
        else:
            data = sys.stdin.buffer.read()
        prefs = load_plist(data)
    except Exception as exc:  # noqa: BLE001 - report, don't crash macconfig-check.sh
        emit("warn", f"could not read corebrightnessdiag status-info ({exc})")
        return 0
    found: list[tuple[str, object]] = []
    collect(prefs, found)
    status, message = judge(found)
    emit(status, message)
    return 0


if __name__ == "__main__":
    sys.exit(main())
