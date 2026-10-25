#!/usr/bin/env python3
"""Tell the caller to check Spotlight → Results from Apps by hand.

lib/spotlight-apps.list is the apps that should be off. This does not read
com.apple.Spotlight. On current macOS, EnabledPreferenceRules is the list of
rows in System Settings → Spotlight, not the on/off state of each row. A row
stays in that list after the toggle is turned off, so treating the list as
"these apps are on" warns when the toggles are already off.

orderedItems is the older category list (APPLICATIONS, DOCUMENTS, and so on),
not these per-app toggles. No other preference this repo can point at is a
reliable on/off store for Results from Apps, so the result is check by hand.

--plist and --json are accepted and ignored, so an old caller cannot turn
that row list into a warning. Nothing here writes.
"""
from __future__ import annotations

import argparse
import sys


STAY_ON = "App Store, Calculator, Dictionary, and System Settings"


def load_apps(path: str) -> list[tuple[str, str]]:
    apps: list[tuple[str, str]] = []
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.split("#", 1)[0].strip()
            if not line or "|" not in line:
                continue
            name, bundle = line.split("|", 1)
            name = name.strip()
            bundle = bundle.strip()
            if name and bundle:
                apps.append((name, bundle))
    return apps


def emit(status: str, message: str) -> None:
    text = message.replace("\n", " ").replace("|", "/")
    print(f"{status}|{text}")


def english_list(names: list[str]) -> str:
    if len(names) < 2:
        return "".join(names)
    if len(names) == 2:
        return f"{names[0]} and {names[1]}"
    return ", ".join(names[:-1]) + ", and " + names[-1]


def hand_message(apps: list[tuple[str, str]]) -> str:
    names = english_list([name for name, _bundle in apps])
    return (
        "check by hand: Results from Apps toggles are not in a preference "
        "this check can read. EnabledPreferenceRules lists the rows, and a "
        f"row stays after the toggle is turned off. Confirm these are off: {names}. "
        f"Leave these on: {STAY_ON}"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="spotlight-rules.py", description=__doc__)
    parser.add_argument("--list", required=True, help="lib/spotlight-apps.list")
    parser.add_argument("--plist", default="", help="ignored; kept so old callers do not warn")
    parser.add_argument("--json", default="", help="ignored; kept so old callers do not warn")
    args = parser.parse_args(argv)
    try:
        apps = load_apps(args.list)
        if not apps:
            emit("warn", "Spotlight app list is empty — results were not checked")
            return 0
        emit("hand", hand_message(apps))
        return 0
    except Exception as exc:  # noqa: BLE001 - report, don't crash the check
        emit("warn", f"could not read the Spotlight app list ({exc})")
        return 0


if __name__ == "__main__":
    sys.exit(main())
