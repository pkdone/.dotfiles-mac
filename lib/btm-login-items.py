#!/usr/bin/env python3
"""Read Login Items / SMAppService state from the BTM database without sfltool.

`sfltool dumpbtm` often pops an admin password dialog on Tahoe. The BTM store at
/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm is world-readable
and enough for our banned-bundle checks.

Usage:
  btm-login-items.py                  # list app-type items: bundle|disposition|enabled|name
  btm-login-items.py com.foo.bar ...  # one line per bundle: bundle=missing|disabled|enabled
"""
from __future__ import annotations

import errno
import sys
from pathlib import Path
from plistlib import UID, load

BTM_DIR = Path("/var/db/com.apple.backgroundtaskmanagement")
# App type from dumpbtm ("Type: app (0x2)")
TYPE_APP = 2


def btm_path() -> Path | None:
    try:
        entries = list(BTM_DIR.iterdir())
    except FileNotFoundError:
        return None
    except NotADirectoryError:
        return None
    except OSError as e:
        if e.errno in (errno.EPERM, errno.EACCES):
            raise PermissionError(e.errno, e.strerror, str(BTM_DIR)) from e
        raise
    cands = sorted(
        (
            e
            for e in entries
            if e.name.startswith("BackgroundItems-v") and e.suffix == ".btm"
        ),
        reverse=True,
    )
    return cands[0] if cands else None


def deref_uid(objects, x):
    while isinstance(x, UID):
        x = objects[x.data]
    return x


def resolve(objects, obj, depth=0):
    obj = deref_uid(objects, obj)
    if depth > 8:
        return "..."
    if isinstance(obj, dict):
        if "NS.keys" in obj and "NS.objects" in obj:
            keys = deref_uid(objects, obj["NS.keys"])
            vals = deref_uid(objects, obj["NS.objects"])
            if isinstance(keys, dict) and "NS.objects" in keys:
                keys = keys["NS.objects"]
            if isinstance(vals, dict) and "NS.objects" in vals:
                vals = vals["NS.objects"]
            return {
                resolve(objects, k, depth + 1): resolve(objects, v, depth + 1)
                for k, v in zip(keys, vals)
            }
        return {
            k: resolve(objects, v, depth + 1)
            for k, v in obj.items()
            if k != "$class"
        }
    if isinstance(obj, list):
        return [resolve(objects, x, depth + 1) for x in obj]
    return obj


def iter_app_items(objects):
    for o in objects:
        if not (isinstance(o, dict) and "disposition" in o and "bundleIdentifier" in o):
            continue
        r = resolve(objects, o)
        if r.get("type") != TYPE_APP:
            continue
        bid = r.get("bundleIdentifier")
        if not isinstance(bid, str):
            continue
        disp = r.get("disposition")
        enabled = bool(disp & 1) if isinstance(disp, int) else None
        yield {
            "bundle": bid,
            "disposition": disp,
            "enabled": enabled,
            "name": r.get("name"),
        }


def main() -> int:
    try:
        path = btm_path()
        if path is None:
            print("btm=missing", file=sys.stderr)
            return 2
        with path.open("rb") as f:
            pl = load(f)
        objects = pl["$objects"]
        items = list(iter_app_items(objects))
        wanted = sys.argv[1:]
        if not wanted:
            for it in items:
                print(
                    f"{it['bundle']}|{it['disposition']}|{it['enabled']}|{it['name']}"
                )
            return 0
        by_bundle = {it["bundle"]: it for it in items}
        for b in wanted:
            it = by_bundle.get(b)
            if it is None:
                print(f"{b}=missing")
            elif it["enabled"] is True:
                print(f"{b}=enabled")
            elif it["enabled"] is False:
                print(f"{b}=disabled")
            else:
                print(f"{b}=unknown")
        return 0
    except OSError as e:
        if e.errno in (errno.EPERM, errno.EACCES):
            print(f"tcc=denied path={e.filename or BTM_DIR}", file=sys.stderr)
            return 3
        raise


if __name__ == "__main__":
    sys.exit(main())
