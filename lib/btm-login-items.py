#!/usr/bin/env python3
"""Read Login Items / SMAppService state from the BTM database without sfltool.

`sfltool dumpbtm` often pops an admin password dialog on Tahoe. The BTM stores under
/var/db/com.apple.backgroundtaskmanagement/ are world-readable (with Full Disk Access
for the calling terminal) and enough for our checks. Read-only.

Store layout:
  macOS 26 and earlier: one BackgroundItems-v<N>.btm holding every item.
  macOS 27 (v18+):      BackgroundItems-v<N>.btm only holds MDM Service Management
                        rules; items live in per-user stores
                        BackgroundItems-v<N>-<GeneratedUID>.btm (yours, plus the
                        FFFFEEEE-DDDD-CCCC-BBBB-AAAA… pseudo-users for system daemons).

Usage:
  btm-login-items.py                  # list app-type items: bundle|disposition|enabled|name
  btm-login-items.py com.foo.bar ...  # one line per bundle: bundle=missing|disabled|enabled
  btm-login-items.py --audit ALLOW    # every ENABLED login/background item, one per line:
                                      #   class|kind|name|developer|team|id|detail
                                      # class: allow (on ALLOW list) | mdm (approved by an MDM
                                      # Service Management rule) | unknown | stale (its app is gone)
                                      # kind: app (opens at login) | login-item | agent | daemon
Exit status: 0 ok, 2 no BTM store, 3 permission denied (needs Full Disk Access).
"""
from __future__ import annotations

import errno
import os
import pwd
import re
import subprocess
import sys
from pathlib import Path
from plistlib import UID, load
from urllib.parse import unquote

BTM_DIR = Path("/var/db/com.apple.backgroundtaskmanagement")
# Item type bits, from dumpbtm ("Type: app (0x2)", "legacy agent (0x10008)", ...)
TYPE_APP = 0x2
TYPE_LOGIN_ITEM = 0x4
TYPE_AGENT = 0x8
TYPE_DAEMON = 0x10
DISP_ENABLED = 0x1
SYSTEM_UUID_PREFIX = "FFFFEEEE-DDDD-CCCC-BBBB-AAAA"
STORE_RE = re.compile(r"^BackgroundItems-v(\d+)(?:-([0-9A-Fa-f-]{36}))?\.btm$")


def _listdir() -> list[Path]:
    try:
        return list(BTM_DIR.iterdir())
    except (FileNotFoundError, NotADirectoryError):
        return []
    except OSError as e:
        if e.errno in (errno.EPERM, errno.EACCES):
            raise PermissionError(e.errno, e.strerror, str(BTM_DIR)) from e
        raise


def my_generated_uid() -> str | None:
    user = pwd.getpwuid(os.getuid()).pw_name
    try:
        out = subprocess.run(
            ["dscl", ".", "-read", f"/Users/{user}", "GeneratedUID"],
            capture_output=True, text=True, timeout=5, check=False,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    m = re.search(r"GeneratedUID:\s*([0-9A-Fa-f-]{36})", out)
    return m.group(1).upper() if m else None


def stores() -> tuple[Path | None, list[Path]]:
    """(rules store, item stores) for the newest BTM version on disk."""
    found: dict[int, dict[str | None, Path]] = {}
    for e in _listdir():
        m = STORE_RE.match(e.name)
        if m:
            found.setdefault(int(m.group(1)), {})[(m.group(2) or "").upper() or None] = e
    if not found:
        return None, []
    by_uuid = found[max(found)]
    base = by_uuid.get(None)
    per_user = {u: p for u, p in by_uuid.items() if u}
    if not per_user:  # pre-macOS 27: one store holds everything
        return base, [base] if base else []
    me = my_generated_uid()
    picked = [p for u, p in sorted(per_user.items())
              if u == me or u.startswith(SYSTEM_UUID_PREFIX)]
    if me is None:  # can't tell which human user is us: take every store
        picked = [p for _, p in sorted(per_user.items())]
    # Your own store first, so its entries win when de-duplicating.
    picked.sort(key=lambda p: 0 if me and me in p.name.upper() else 1)
    return base, picked


def btm_path() -> Path | None:
    """Back-compat: the first item store (yours on macOS 27)."""
    _, items = stores()
    return items[0] if items else None


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
        if "NS.objects" in obj and len(obj) <= 2:
            return [resolve(objects, x, depth + 1) for x in obj["NS.objects"]]
        if "NS.relative" in obj:  # NSURL
            base = resolve(objects, obj.get("NS.base"), depth + 1)
            rel = resolve(objects, obj["NS.relative"], depth + 1)
            return rel if base in (None, "$null") else f"{base}|{rel}"
        return {
            k: resolve(objects, v, depth + 1)
            for k, v in obj.items()
            if k != "$class"
        }
    if isinstance(obj, list):
        return [resolve(objects, x, depth + 1) for x in obj]
    return obj


def s(x) -> str:
    return x if isinstance(x, str) and x != "$null" else ""


def load_store(path: Path):
    with path.open("rb") as f:
        pl = load(f)
    return pl["$objects"], pl.get("$top", {})


def iter_items(paths: list[Path]):
    """Every BTM item across the given stores, de-duplicated by identifier+url."""
    seen = set()
    for path in paths:
        objects, _ = load_store(path)
        for o in objects:
            if not (isinstance(o, dict) and "disposition" in o and "type" in o):
                continue
            r = resolve(objects, o)
            t, disp = r.get("type"), r.get("disposition")
            if not isinstance(t, int) or not isinstance(disp, int):
                continue
            key = (s(r.get("identifier")), s(r.get("url")))
            if key in seen:
                continue
            seen.add(key)
            ident = s(r.get("identifier"))
            yield {
                "type": t,
                "disposition": disp,
                "enabled": bool(disp & DISP_ENABLED),
                "bundle": s(r.get("bundleIdentifier")),
                "id": ident.split(".", 1)[1] if "." in ident else ident,
                "parent": s(r.get("container")),
                "name": s(r.get("name")),
                "developer": s(r.get("developerName")),
                "team": s(r.get("teamIdentifier")),
                "url": s(r.get("url")),
            }


def app_items(paths):
    for it in iter_items(paths):
        if it["type"] == TYPE_APP and it["bundle"]:
            yield it


def mdm_rules(base: Path | None) -> list[dict]:
    """Service Management rules pushed by MDM (Kandji etc.), from the base store."""
    if base is None:
        return []
    objects, top = load_store(base)
    root = resolve(objects, top)
    payloads = root.get("mdmPayloadsByIdentifier") if isinstance(root, dict) else None
    rules = []
    for p in (payloads or {}).values():
        rs = p.get("Rules") if isinstance(p, dict) else None
        if isinstance(rs, dict):
            rs = rs.get("NS.objects", [])
        for r in rs or []:
            if isinstance(r, dict) and s(r.get("RuleType")) and s(r.get("RuleValue")):
                rules.append({"type": s(r["RuleType"]), "value": s(r["RuleValue"]),
                              "team": s(r.get("TeamIdentifier"))})
    return rules


def read_allow(path: str) -> list[dict]:
    """lib/login-items-allow.list: type|value|note (team, bundle, label, label-prefix)."""
    kinds = {"team": "TeamIdentifier", "bundle": "BundleIdentifier",
             "label": "Label", "label-prefix": "LabelPrefix"}
    rules = []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = [x.strip() for x in line.split("|")]
            if len(parts) < 2 or parts[0] not in kinds or not parts[1]:
                print(f"allowlist: line {n}: expected type, value and note separated "
                      f"by pipes (type: {', '.join(kinds)})", file=sys.stderr)
                continue
            rules.append({"type": kinds[parts[0]], "value": parts[1], "team": ""})
    return rules


def matches(rule: dict, it: dict) -> bool:
    if rule["team"] and rule["team"] != it["team"]:
        return False
    v, t = rule["value"], rule["type"]
    parent_bundle = it["parent"].split(".", 1)[1] if re.match(r"^\d+\.", it["parent"]) else ""
    if t == "TeamIdentifier":
        return it["team"] == v
    if t == "BundleIdentifier":
        return v in (it["bundle"], parent_bundle) or (not it["bundle"] and it["id"] == v)
    if t == "Label":
        return it["id"] == v
    if t == "LabelPrefix":
        return it["id"].startswith(v)
    return False


def kind_of(t: int) -> str | None:
    if t & TYPE_DAEMON:
        return "daemon"
    if t & TYPE_AGENT:
        return "agent"
    if t & TYPE_LOGIN_ITEM:
        return "login-item"
    if t == TYPE_APP:
        return "app"
    return None  # plugins, Spotlight importers, dock tiles, app refresh, developer groups


def stale_path(it: dict) -> str:
    """Absolute file:// URL of an app/agent that no longer exists on disk, else ''."""
    url = it["url"]
    if "|" in url or not url.startswith("file:///"):
        return ""  # relative to its container app: can't go stale on its own
    p = unquote(url[len("file://"):]).rstrip("/")
    return "" if os.path.exists(p) else p


def audit(allow_path: str, base, paths) -> int:
    allow = read_allow(allow_path)
    mdm = mdm_rules(base)
    for it in iter_items(paths):
        kind = kind_of(it["type"])
        if kind is None or not it["enabled"]:
            continue
        ident = it["bundle"] or it["id"]
        gone = stale_path(it)
        if gone:
            cls, detail = "stale", f"points to {gone}, which no longer exists"
        elif any(matches(r, it) for r in allow):
            cls, detail = "allow", ""
        elif any(matches(r, it) for r in mdm):
            cls, detail = "mdm", "approved by an MDM Service Management rule"
        else:
            cls, detail = "unknown", ""
        fields = [cls, kind, it["name"] or ident, it["developer"], it["team"], ident, detail]
        print("|".join(f.replace("|", "/") for f in fields))
    return 0


def main() -> int:
    try:
        base, paths = stores()
        if not paths:
            print("btm=missing", file=sys.stderr)
            return 2
        args = sys.argv[1:]
        if args[:1] == ["--audit"]:
            if len(args) != 2:
                print("usage: btm-login-items.py --audit ALLOWLIST", file=sys.stderr)
                return 64
            return audit(args[1], base, paths)
        items = list(app_items(paths))
        if not args:
            for it in items:
                print(f"{it['bundle']}|{it['disposition']}|{it['enabled']}|{it['name']}")
            return 0
        by_bundle = {}
        for it in items:  # first (your own store) wins
            by_bundle.setdefault(it["bundle"], it)
        for b in args:
            it = by_bundle.get(b)
            if it is None:
                print(f"{b}=missing")
            elif it["enabled"]:
                print(f"{b}=enabled")
            else:
                print(f"{b}=disabled")
        return 0
    except OSError as e:
        if e.errno in (errno.EPERM, errno.EACCES):
            print(f"tcc=denied path={e.filename or BTM_DIR}", file=sys.stderr)
            return 3
        raise


if __name__ == "__main__":
    sys.exit(main())
