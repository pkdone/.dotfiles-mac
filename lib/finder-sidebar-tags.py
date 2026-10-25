#!/usr/bin/env python3
"""Read whether Finder shows any tags in the sidebar.

Finder → Settings → Tags → "Show these tags in the sidebar" is
FavoriteTagNames in com.apple.finder. An empty list means every box is
unticked. A missing key is Finder's default list, so the boxes are still
ticked. That is a warning, not a guess.

ShowRecentTags is read only when the key is present. On means recent tags
can still appear. A missing ShowRecentTags is not a failure: that value
was not confirmed on a good setup, and the checkbox list is FavoriteTagNames.

The live read is `defaults export com.apple.finder -`, which is the
preference the system is using. --plist reads a file instead (tests).
Nothing here writes, and nothing needs sudo.

Output is one line:

    ok|message
    warn|message
    info|message
"""
from __future__ import annotations

import argparse
import plistlib
import subprocess
import sys

CLICK = (
    "Finder → Settings → Tags → untick every box under "
    "Show these tags in the sidebar (Red, Orange, Yellow, Green, Blue, "
    "Purple, Grey, Work, Home, Important)."
)
FIX = " macconfig does not change the sidebar."
MISSING = object()


def emit(status: str, message: str) -> None:
    text = message.replace("\n", " ").replace("|", "/")
    print(f"{status}|{text}")


def as_bool(value: object) -> bool | None:
    if isinstance(value, bool):
        return value
    if type(value) is int and value in (0, 1):
        return bool(value)
    return None


def load_export() -> tuple[str, object]:
    """('ok', dict) or ('info', message). Never writes."""
    try:
        proc = subprocess.run(
            ["defaults", "export", "com.apple.finder", "-"],
            check=False,
            capture_output=True,
        )
    except OSError as exc:
        return "info", f"Finder tag preferences could not be read ({exc})."
    if proc.returncode != 0 or not proc.stdout:
        err = proc.stderr.decode("utf-8", "replace").strip()
        detail = err or f"defaults export exited {proc.returncode}"
        return "info", f"Finder tag preferences could not be read ({detail})."
    try:
        data = plistlib.loads(proc.stdout)
    except (plistlib.InvalidFileException, ValueError, TypeError) as exc:
        return "info", f"Finder tag preferences could not be read ({exc})."
    if not isinstance(data, dict):
        return "info", "Finder tag preferences could not be read (not a dictionary)."
    return "ok", data


def load_plist(path: str) -> tuple[str, object]:
    try:
        with open(path, "rb") as fh:
            data = plistlib.load(fh)
    except FileNotFoundError:
        return "info", "Finder tag preferences could not be read (file missing)."
    except OSError as exc:
        return "info", f"Finder tag preferences could not be read ({exc.strerror or exc})."
    except (plistlib.InvalidFileException, ValueError, TypeError) as exc:
        return "info", f"Finder tag preferences could not be read ({exc})."
    if not isinstance(data, dict):
        return "info", "Finder tag preferences could not be read (not a dictionary)."
    return "ok", data


def judge(prefs: dict) -> tuple[str, str]:
    problems: list[str] = []
    names = prefs.get("FavoriteTagNames", MISSING)
    if names is MISSING:
        problems.append(
            "FavoriteTagNames is not set, so Finder is still showing its "
            "default tags in the sidebar."
        )
    elif isinstance(names, list):
        shown = [item.strip() for item in names if isinstance(item, str) and item.strip()]
        if any(not isinstance(item, str) for item in names):
            return (
                "info",
                "FavoriteTagNames is not a list of names, so the sidebar "
                f"tags stay by hand. {CLICK}{FIX}",
            )
        if shown:
            problems.append(
                "These tags are still shown in the sidebar: " + ", ".join(shown) + "."
            )
    else:
        return (
            "info",
            "FavoriteTagNames is not a list, so the sidebar tags stay by hand. "
            f"{CLICK}{FIX}",
        )
    recent = prefs.get("ShowRecentTags", MISSING)
    if recent is not MISSING:
        flag = as_bool(recent)
        if flag is None:
            return (
                "info",
                "ShowRecentTags is not a yes or no value, so the sidebar "
                f"tags stay by hand. {CLICK}{FIX}",
            )
        if flag:
            problems.append(
                "ShowRecentTags is on, so recent tags can still appear in the sidebar."
            )
    if problems:
        return "warn", " ".join(problems) + " " + CLICK + FIX
    return "ok", "No tags are shown in the Finder sidebar."


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="finder-sidebar-tags.py", description=__doc__)
    parser.add_argument("--plist", default="", help="Finder preferences plist to read (tests)")
    args = parser.parse_args(argv)
    if args.plist:
        status, payload = load_plist(args.plist)
    else:
        status, payload = load_export()
    if status != "ok" or not isinstance(payload, dict):
        message = payload if isinstance(payload, str) else "Finder tag preferences could not be read."
        emit("info", f"{message} {CLICK}{FIX}")
        return 0
    out_status, message = judge(payload)
    emit(out_status, message)
    return 0


if __name__ == "__main__":
    sys.exit(main())
