#!/usr/bin/env python3
"""Read-only check that the desktop picture is Tahoe Night (Landscape).

The wallpaper store is
~/Library/Application Support/com.apple.wallpaper/Store/Index.plist.
The asset id is searched for as text inside that file (plain text and
UTF-16), so a binary plist still matches when the id is stored as text.
Nothing here writes. A miss is a warning.

Tahoe Night (Landscape) is a wallpaper-catalog asset, not a file under
/System/Library/Desktop Pictures. System Events "set picture of every
desktop" cannot select that asset, and writing this store is not a
supported way to change it, so the picture stays a manual step.
macconfig --fix does not change the picture.
"""
from __future__ import annotations

import argparse
import sys

ASSET_ID = "CF6347E2-4F81-4410-8892-4830991B6C5A"
PLAIN_NAME = "Tahoe Night (Landscape)"


def emit(status: str, message: str) -> None:
    text = str(message).replace("\n", " ").replace("|", "/")
    print(f"{status}||{text}")


def has_asset(data: bytes, asset_id: str) -> bool:
    variants = {asset_id, asset_id.lower(), asset_id.upper()}
    for variant in variants:
        raw = variant.encode("ascii")
        if raw in data:
            return True
        if variant.encode("utf-16-le") in data:
            return True
        if variant.encode("utf-16-be") in data:
            return True
    return False


def judge(data: bytes | None, missing: bool, asset_id: str) -> tuple[str, str]:
    if missing or data is None:
        return (
            "warn",
            "wallpaper store is missing, so the desktop picture could not be"
            f" checked (want {PLAIN_NAME}). System Settings → Wallpaper."
            " There is no reliable command for this system picture."
            " macconfig --fix does not change this",
        )
    if has_asset(data, asset_id):
        return (
            "ok",
            f"desktop picture is {PLAIN_NAME}",
        )
    return (
        "warn",
        f"desktop picture is not {PLAIN_NAME} (asset {asset_id} is not in the"
        " wallpaper store). System Settings → Wallpaper."
        " There is no reliable command for this system picture."
        " macconfig --fix does not change this",
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="wallpaper-asset.py", description=__doc__)
    parser.add_argument(
        "--text",
        default="",
        help="read this file instead of the wallpaper store",
    )
    parser.add_argument("--asset", default=ASSET_ID, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    path = args.text or (
        __import__("os").path.expanduser(
            "~/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
        )
    )
    try:
        with open(path, "rb") as fh:
            data = fh.read()
        missing = False
    except FileNotFoundError:
        data = None
        missing = True
    except Exception as exc:  # noqa: BLE001 - report, don't crash the check
        emit("warn", f"could not read the wallpaper store ({exc})")
        return 0
    status, message = judge(data, missing, args.asset)
    emit(status, message)
    return 0


if __name__ == "__main__":
    sys.exit(main())
