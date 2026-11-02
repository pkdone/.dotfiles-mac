#!/usr/bin/env python3
"""Read-only check of System Settings → Menu Bar → Allow in the Menu Bar.

On macOS 26 (Tahoe) the toggles live in the Control Center group plist

    ~/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist

The key ``trackedApplications`` is a data blob. The blob is itself a binary
plist: an array that alternates

    {'bundle': {'_0': <bundle id>}}

and

    {'location': {'bundle': {'_0': <id>}},
     'menuItemLocations': [...],
     'isAllowed': bool}

``isAllowed`` is the toggle. The id that names the app is ``location`` →
``bundle`` → ``_0`` (the same id as the preceding bundle record). Docker
Desktop is ``com.docker.docker``; a bundle inside ``menuItemLocations`` can
be ``com.electron.dockerdesktop`` and is not the toggle.

This reads that file with plistlib and never writes it, never calls
``defaults``, and never restarts ControlCenter. Writing the blob is
undocumented and Control Center may overwrite it, so there is no --fix.

Apps that must be off (or, if a row says so, on) are lib/menubar-allow.list.
An app in that list whose toggle is the wrong way is drift. An app that is
not in ``trackedApplications`` is not installed, or has not been listed yet:
that is info, not drift. A missing or unreadable plist is a warning. The
process still exits 0, so a bad plist cannot crash macconfig-check.sh.

``MENUBAR_ALLOW_PLIST`` overrides the path (tests). ``--plist`` wins.

Output, one line per result, fields separated by ``|``:

    ok|bundle-id|message       listed app, isAllowed matches
    drift|bundle-id|message    listed app, isAllowed is the wrong way
    info|bundle-id|message     listed app not in trackedApplications
    warn|-|message             plist or list missing, or the blob did not parse
"""
from __future__ import annotations

import argparse
import os
import plistlib
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_LIST = os.path.join(HERE, "menubar-allow.list")
DEFAULT_RELATIVE = (
    "Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/"
    "group.com.apple.controlcenter.plist"
)
BUNDLE_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*$")
HOW_OFF = "System Settings → Menu Bar → Allow in the Menu Bar → turn off "
HOW_ON = "System Settings → Menu Bar → Allow in the Menu Bar → turn on "


def emit(status: str, bundle: str, message: str) -> None:
    text = str(message).replace("\n", " ").replace("|", "/")
    ident = bundle or "-"
    ident = ident.replace("|", "/").replace("\n", " ")
    print(f"{status}|{ident}|{text}")


def default_path() -> str:
    override = os.environ.get("MENUBAR_ALLOW_PLIST", "").strip()
    if override:
        return override
    return os.path.join(os.path.expanduser("~"), DEFAULT_RELATIVE)


def load_list(path: str) -> list[tuple[str, str, str]]:
    """Rows in file order: bundle id, 'on' or 'off', display name."""
    rows: list[tuple[str, str, str]] = []
    seen: set[str] = set()
    name = os.path.basename(path)
    with open(path, encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            body = raw.split("#", 1)[0].strip()
            if not body:
                continue
            parts = [part.strip() for part in body.split("|")]
            if len(parts) != 3:
                raise ValueError(f"{name}:{lineno}: expected bundle id, on or off, and a display name")
            bundle, expect, label = parts
            if len(bundle.split()) != 1 or not BUNDLE_RE.match(bundle):
                raise ValueError(f"{name}:{lineno}: expected one bundle id")
            if expect not in ("on", "off"):
                raise ValueError(f"{name}:{lineno}: expected on or off")
            if not label:
                raise ValueError(f"{name}:{lineno}: expected a display name")
            if bundle in seen:
                raise ValueError(f"{name}:{lineno}: duplicate bundle id {bundle}")
            seen.add(bundle)
            rows.append((bundle, expect, label))
    return rows


def _bundle_0(node: object) -> str | None:
    """bundle id from {'_0': id} or {'bundle': {'_0': id}}."""
    if not isinstance(node, dict):
        return None
    direct = node.get("_0")
    if isinstance(direct, str) and direct:
        return direct
    nested = node.get("bundle")
    if isinstance(nested, dict):
        inner = nested.get("_0")
        if isinstance(inner, str) and inner:
            return inner
    return None


def bundle_from_identity(item: object) -> str | None:
    if not isinstance(item, dict):
        return None
    return _bundle_0(item.get("bundle"))


def bundle_from_state(item: object) -> str | None:
    """The toggle's bundle id. menuItemLocations is a different id and is ignored."""
    if not isinstance(item, dict):
        return None
    return _bundle_0(item.get("location"))


def is_identity(item: object) -> bool:
    return (
        isinstance(item, dict)
        and "bundle" in item
        and "isAllowed" not in item
        and "location" not in item
    )


def is_state(item: object) -> bool:
    return isinstance(item, dict) and ("isAllowed" in item or "location" in item)


def parse_tracked(items: object) -> dict[str, object] | None:
    """Map bundle id → isAllowed. None when the blob is not the alternating array."""
    if not isinstance(items, list):
        return None
    found: dict[str, object] = {}
    index = 0
    count = len(items)
    while index < count:
        current = items[index]
        nxt = items[index + 1] if index + 1 < count else None
        if is_identity(current) and is_state(nxt):
            allowed = nxt.get("isAllowed") if isinstance(nxt, dict) else None
            state_id = bundle_from_state(nxt)
            ident_id = bundle_from_identity(current)
            if state_id:
                found[state_id] = allowed
            if ident_id and ident_id != state_id:
                found[ident_id] = allowed
            index += 2
            continue
        if is_state(current):
            state_id = bundle_from_state(current)
            if state_id:
                found[state_id] = current.get("isAllowed")
            index += 1
            continue
        index += 1
    return found


def load_tracked(prefs: object) -> dict[str, object] | None:
    """Pull the nested plist out of trackedApplications. None if it is not there."""
    if not isinstance(prefs, dict) or "trackedApplications" not in prefs:
        return None
    blob = prefs.get("trackedApplications")
    if isinstance(blob, (bytes, bytearray)):
        try:
            inner = plistlib.loads(blob)
        except Exception:
            return None
        return parse_tracked(inner)
    if isinstance(blob, list):
        return parse_tracked(blob)
    return None


def report(rows: list[tuple[str, str, str]], found: dict[str, object]) -> None:
    for bundle, expect, label in rows:
        if bundle not in found:
            emit(
                "info",
                bundle,
                f"{label} ({bundle}): not installed, or not in Allow in the Menu Bar yet",
            )
            continue
        allowed = found[bundle]
        if not isinstance(allowed, bool):
            emit(
                "warn",
                bundle,
                f"{label} ({bundle}): isAllowed unreadable"
                " — can't check Allow in the Menu Bar",
            )
            continue
        want_on = expect == "on"
        if allowed == want_on:
            state = "on" if allowed else "off"
            emit(
                "ok",
                bundle,
                f"{label} ({bundle}): Allow in the Menu Bar is {state}",
            )
            continue
        if want_on:
            emit(
                "drift",
                bundle,
                f"{label} ({bundle}) is not allowed in the menu bar — {HOW_ON}{label}",
            )
        else:
            emit(
                "drift",
                bundle,
                f"{label} ({bundle}) is allowed in the menu bar — {HOW_OFF}{label}",
            )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="menubar-allow.py", description=__doc__)
    parser.add_argument("--plist", default=None, help="Control Center group plist to read")
    parser.add_argument("--list", default=DEFAULT_LIST, help="bundle|on|off|name list")
    args = parser.parse_args(argv)
    plist_path = args.plist or default_path()
    try:
        rows = load_list(args.list)
    except FileNotFoundError as exc:
        emit("warn", "-", f"menubar allow list missing ({exc.filename})")
        return 0
    except Exception as exc:  # noqa: BLE001 - report, don't crash macconfig-check.sh
        emit("warn", "-", f"could not read the menubar allow list ({exc})")
        return 0
    if not rows:
        emit("warn", "-", "menubar allow list has no bundle ids")
        return 0
    try:
        with open(plist_path, "rb") as fh:
            data = fh.read()
        prefs = plistlib.loads(data)
    except FileNotFoundError:
        emit(
            "warn",
            "-",
            f"Allow in the Menu Bar list missing at {plist_path}"
            " — can't check it",
        )
        return 0
    except PermissionError:
        emit(
            "warn",
            "-",
            "Allow in the Menu Bar list unreadable"
            " — can't check it",
        )
        return 0
    except Exception as exc:  # noqa: BLE001 - a torn or foreign plist is a warning
        emit("warn", "-", f"could not read Allow in the Menu Bar list ({exc})")
        return 0
    found = load_tracked(prefs)
    if found is None:
        emit(
            "warn",
            "-",
            "Allow in the Menu Bar list has no readable trackedApplications"
            " — can't check it",
        )
        return 0
    report(rows, found)
    return 0


if __name__ == "__main__":
    sys.exit(main())
