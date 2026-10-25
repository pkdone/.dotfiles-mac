#!/usr/bin/env python3
"""Read-only count of widgets placed on the desktop.

Hiding widgets (com.apple.WindowManager StandardHideWidgets) does not delete
them. The placed widgets are the ``widgets`` → ``instances`` array in

    ~/Library/Containers/com.apple.notificationcenterui/Data/Library/Preferences/com.apple.notificationcenterui.plist

One data blob per widget. Each blob is a nested plist. When that plist has a
readable extension or kind bundle id, the warning names it. A blob that does
not is still counted. ``DesktopWidgetPlacementStorage`` is not the count.

Nothing here writes that plist or kills NotificationCenter or chronod.
macconfig --fix does not either. Removal is manual step remove-widgets:
Control-click (or right-click) the widget, then Remove Widget.

Output is one line, ``status||message``:

    ok    instances is missing or empty (a missing file counts as no widgets)
    warn  N widgets on the desktop, with kind names when a blob has one
    hand  the plist is there but cannot be read — check by hand

``DESKTOP_WIDGETS_PLIST`` overrides the path (tests). ``--plist`` wins.
"""
from __future__ import annotations

import argparse
import os
import plistlib
import re
import sys

DEFAULT_RELATIVE = (
    "Library/Containers/com.apple.notificationcenterui/Data/Library/"
    "Preferences/com.apple.notificationcenterui.plist"
)

# Three components minimum (com.apple.weather), so a bare "com.apple" is not a kind.
BUNDLE_ID = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z][A-Za-z0-9_-]*){2,}$")


def emit(status: str, message: str) -> None:
    text = str(message).replace("\n", " ").replace("|", "/")
    print(f"{status}||{text}")


def default_path() -> str:
    override = os.environ.get("DESKTOP_WIDGETS_PLIST", "").strip()
    if override:
        return override
    return os.path.join(os.path.expanduser("~"), DEFAULT_RELATIVE)


def uid_index(value: object) -> int | None:
    if isinstance(value, plistlib.UID):
        data = value.data
        if isinstance(data, int):
            return data
        return None
    if isinstance(value, dict) and len(value) == 1 and "CF$UID" in value:
        number = value.get("CF$UID")
        if isinstance(number, int):
            return number
    return None


def resolve(value: object, objects: list | None, depth: int = 0) -> object:
    """Follow NSKeyedArchiver UID references, a few hops only."""
    if objects is None or depth > 8:
        return value
    index = uid_index(value)
    if index is None or index < 0 or index >= len(objects):
        return value
    return resolve(objects[index], objects, depth + 1)


def as_list(value: object, objects: list | None) -> list | None:
    value = resolve(value, objects)
    if isinstance(value, list):
        return value
    return None


def is_kind_key(key: str) -> bool:
    folded = key.lower()
    return "extension" in folded or "kind" in folded


def as_bundle(value: object) -> str | None:
    if isinstance(value, str) and BUNDLE_ID.fullmatch(value):
        return value
    return None


def iter_pairs(obj: dict, objects: list | None):
    keys = as_list(obj.get("NS.keys"), objects) if "NS.keys" in obj else None
    vals = as_list(obj.get("NS.objects"), objects) if "NS.objects" in obj else None
    if keys is not None and vals is not None:
        for key, val in zip(keys, vals):
            yield resolve(key, objects), resolve(val, objects)
    for key, val in obj.items():
        if not isinstance(key, str):
            continue
        if key.startswith("$") or key.startswith("NS."):
            continue
        yield key, resolve(val, objects)


def first_kind(obj: object, objects: list | None = None, seen: set | None = None) -> str | None:
    if seen is None:
        seen = set()
    if isinstance(obj, (dict, list)):
        marker = id(obj)
        if marker in seen:
            return None
        seen.add(marker)
    if isinstance(obj, dict) and objects is None and isinstance(obj.get("$objects"), list):
        objects = obj["$objects"]
        top = obj.get("$top")
        if isinstance(top, dict) and "root" in top:
            found = first_kind(resolve(top["root"], objects), objects, seen)
            if found:
                return found
    if isinstance(obj, dict):
        pairs = list(iter_pairs(obj, objects))
        for key, value in pairs:
            if isinstance(key, str) and is_kind_key(key):
                found = as_bundle(value)
                if found:
                    return found
        for _key, value in pairs:
            found = first_kind(value, objects, seen)
            if found:
                return found
        return None
    if isinstance(obj, list):
        for item in obj:
            found = first_kind(resolve(item, objects), objects, seen)
            if found:
                return found
    return None


def instance_kind(item: object) -> str | None:
    blob: object = item
    if isinstance(item, bytes):
        if not item:
            return None
        try:
            blob = plistlib.loads(item)
        except Exception:
            return None
    elif not isinstance(item, (dict, list)):
        return None
    try:
        return first_kind(blob)
    except Exception:
        return None


def format_warn(count: int, names: list[str]) -> str:
    noun = "widget" if count == 1 else "widgets"
    base = f"{count} {noun} on the desktop"
    if not names:
        return base
    shown = ", ".join(names)
    extra = count - len(names)
    if extra > 0:
        return f"{base}: {shown}, and {extra} more"
    return f"{base}: {shown}"


def judge(path: str) -> tuple[str, str]:
    try:
        with open(path, "rb") as fh:
            data = fh.read()
    except FileNotFoundError:
        return "ok", "no widgets on the desktop"
    except OSError as exc:
        reason = exc.strerror or "unreadable"
        return "hand", f"can't read the desktop widget list ({reason}) — check by hand"
    if not data:
        return "hand", "can't read the desktop widget list (empty file) — check by hand"
    try:
        root = plistlib.loads(data)
    except Exception:
        return "hand", "can't read the desktop widget list (not a plist) — check by hand"
    if not isinstance(root, dict):
        return "hand", "can't read the desktop widget list (plist is not a dictionary) — check by hand"
    if "widgets" not in root or root.get("widgets") is None:
        return "ok", "no widgets on the desktop"
    widgets = root.get("widgets")
    if not isinstance(widgets, dict):
        return "hand", "can't read the desktop widget list (widgets is not a dictionary) — check by hand"
    if "instances" not in widgets or widgets.get("instances") is None:
        return "ok", "no widgets on the desktop"
    instances = widgets.get("instances")
    if not isinstance(instances, list):
        return "hand", "can't read the desktop widget list (widgets.instances is not a list) — check by hand"
    if len(instances) == 0:
        return "ok", "no widgets on the desktop"
    names: list[str] = []
    for item in instances:
        kind = instance_kind(item)
        if kind:
            names.append(kind)
    return "warn", format_warn(len(instances), names)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="desktop-widgets.py", description=__doc__)
    parser.add_argument("--plist", default="", help="read this file instead of the Notification Center plist")
    args = parser.parse_args(argv)
    path = args.plist or default_path()
    try:
        status, message = judge(path)
    except Exception as exc:  # noqa: BLE001 - report, don't crash the check
        emit("hand", f"can't read the desktop widget list ({exc}) — check by hand")
        return 0
    emit(status, message)
    return 0


if __name__ == "__main__":
    sys.exit(main())
