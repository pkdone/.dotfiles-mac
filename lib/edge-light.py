#!/usr/bin/env python3
"""Edge Light stays check by hand. Nothing here writes.

Edge Light is the macOS video effect that lights the edges of the screen
like a ring light during a video call. Paul wants it Off.

On this Mac the on/off state lives in the protected file

    ~/Library/Group Containers/group.com.apple.secure-control-center-preferences/Library/Preferences/group.com.apple.secure-control-center-preferences.av.plist

Reading that file is permission denied. RingLightHelper's container and
group (group.com.apple.ringlight) hold no preferences. A file that happens
to be readable is still not a reliable on/off store: this repo has no key
it can trust, and the real file cannot be read. The step is therefore
always shown.

Output is one line:

    hand|can't be checked, so always shown

--av and --ringlight override the two paths (tests). EDGE_LIGHT_AV_PLIST
and EDGE_LIGHT_RINGLIGHT_DIR do the same when the flags are omitted.
"""
from __future__ import annotations

import argparse
import os
import sys

AV_RELATIVE = (
    "Library/Group Containers/group.com.apple.secure-control-center-preferences/"
    "Library/Preferences/group.com.apple.secure-control-center-preferences.av.plist"
)
RING_RELATIVE = "Library/Group Containers/group.com.apple.ringlight"
HAND = "can't be checked, so always shown"


def emit(status: str, message: str) -> None:
    text = message.replace("\n", " ").replace("|", "/")
    print(f"{status}|{text}")


def read_attempt(path: str) -> str:
    """Try to read one byte. Never creates or writes the path."""
    try:
        with open(path, "rb") as fh:
            fh.read(1)
    except FileNotFoundError:
        return "missing"
    except PermissionError:
        return "denied"
    except OSError:
        return "unreadable"
    return "readable"


def plist_names(root: str) -> list[str]:
    """Preference file names under root. Missing or unreadable is no prefs."""
    if not root or not os.path.isdir(root):
        return []
    found: list[str] = []
    try:
        walker = os.walk(root)
    except OSError:
        return []
    for dirpath, dirnames, filenames in walker:
        dirnames[:] = [name for name in dirnames if not os.path.islink(os.path.join(dirpath, name))]
        for name in filenames:
            if name.endswith(".plist"):
                found.append(name)
    return found


def ring_roots(home: str, override: str) -> list[str]:
    if override:
        return [override]
    roots = [os.path.join(home, RING_RELATIVE)]
    containers = os.path.join(home, "Library", "Containers")
    try:
        names = os.listdir(containers)
    except OSError:
        names = []
    for name in names:
        if "ringlight" in name.lower():
            roots.append(os.path.join(containers, name))
    return roots


def classify(av_path: str, roots: list[str]) -> tuple[str, str]:
    """Always check by hand. The reads stay, so a fixture can prove no write.

    A missing, denied, unreadable, or readable protected file is not the
    toggle: there is no key this repo can trust, and on this Mac the file
    cannot be read. Preferences under RingLightHelper's group, including
    none, are not a second copy of the setting. The step stays on the list.
    """
    read_attempt(av_path)
    for root in roots:
        plist_names(root)
    return "hand", HAND


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="edge-light.py", description=__doc__)
    parser.add_argument("--av", default="", help="protected video-effects plist (tests)")
    parser.add_argument("--ringlight", default="", help="RingLightHelper group or container (tests)")
    args = parser.parse_args(argv)
    home = os.environ.get("HOME", "")
    av_path = args.av or os.environ.get("EDGE_LIGHT_AV_PLIST", "")
    ring = args.ringlight or os.environ.get("EDGE_LIGHT_RINGLIGHT_DIR", "")
    if not av_path:
        av_path = os.path.join(home, AV_RELATIVE)
    try:
        status, message = classify(av_path, ring_roots(home, ring))
        emit(status, message)
    except Exception:  # noqa: BLE001 - a failed read is still check by hand
        emit("hand", HAND)
    return 0


if __name__ == "__main__":
    sys.exit(main())
