#!/usr/bin/env python3
"""Read Login Items / SMAppService state from the BTM database without sfltool.

`sfltool dumpbtm` often pops an admin password dialog on Tahoe. The BTM stores under
/var/db/com.apple.backgroundtaskmanagement/ are the same records dumpbtm prints.
BTM_DIR overrides that directory. Unset, the system directory is read.
They are world-readable with Full Disk Access and enough for our checks. Read-only.
The login-items commands below never run sfltool. `--karabiner` reads those records
first, and only runs `sfltool dumpbtm` with a short timeout when the records cannot
be read. If that does not finish, the result is an info line.

Store layout:
  macOS 26 and earlier: one BackgroundItems-v<N>.btm holding every item.
  macOS 27 (v18+):      BackgroundItems-v<N>.btm only holds MDM Service Management
                        rules; items live in per-user stores
                        BackgroundItems-v<N>-<GeneratedUID>.btm (yours, plus the
                        FFFFEEEE-DDDD-CCCC-BBBB-AAAA… pseudo-users for system daemons).

Usage:
  btm-login-items.py                  # list app-type items: bundle|disposition|enabled|name
  btm-login-items.py com.foo.bar ...  # one line per bundle: bundle=missing|disabled|enabled
  btm-login-items.py --karabiner      # Karabiner-Core-Service and
                                      # Karabiner-VirtualHIDDevice-Daemon must be
                                      # enabled and allowed. One line per result:
                                      #   ok|name|message / warn|name|message / info|-|message
                                      # --dump FILE parses that dumpbtm text and does
                                      # not read the database or run sfltool.
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

def _btm_dir() -> Path:
    override = os.environ.get("BTM_DIR", "").strip()
    if override:
        return Path(override)
    return Path("/var/db/com.apple.backgroundtaskmanagement")


BTM_DIR = _btm_dir()
# Item type bits, from dumpbtm ("Type: app (0x2)", "legacy agent (0x10008)", ...)
TYPE_APP = 0x2
TYPE_LOGIN_ITEM = 0x4
TYPE_AGENT = 0x8
TYPE_DAEMON = 0x10
DISP_ENABLED = 0x1
# dumpbtm disposition words, low bit first: enabled, allowed, visible, notified.
# 0xB (11) is enabled, allowed, visible, and notified. 0x2 is disabled, allowed.
DISP_ALLOWED = 0x2
KARABINER_BACKGROUND = (
    "Karabiner-Core-Service",
    "Karabiner-VirtualHIDDevice-Daemon",
)
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


def launchd_id(ident: str) -> str:
    """Drop a numeric BTM type prefix (8.com.foo -> com.foo). Leave real labels alone.

    Identifiers from the store often look like ``2.com.foo`` or ``8.com.foo.bar``.
    A launchd label such as ``com.foo.BackgroundActivityCheck`` has no numeric
    prefix; stripping the first word of that would hide the ``com.`` / ``co.``
    the allow-list matches on.
    """
    if re.match(r"^\d+\.", ident):
        return ident.split(".", 1)[1]
    return ident


# A boolean name in the BTM store is not a display name. plistlib gives True,
# and a naive stringify prints "true" / "True". Treat those as missing.
_BOOLISH_NAME = {"true", "false", "yes", "no"}


def usable_name(value: str) -> str:
    text = value.strip()
    if not text or text == "$null" or text.lower() in _BOOLISH_NAME:
        return ""
    return text


def display_name(it: dict) -> str:
    """Name to show for a login item.

    Some agents (Cursor's BackgroundActivityCheck helper among them) store
    ``name`` as a boolean. That used to surface as the word "true". Prefer a
    real name, then the executable's file name, then the app name in the URL,
    then a helper name on the identifier.
    """
    named = usable_name(it.get("name") or "")
    if named:
        return named
    exe = it.get("executable") or ""
    named = usable_name(os.path.basename(exe.rstrip("/")))
    if named:
        return named
    url = it.get("url") or ""
    path = unquote(url.split("|")[-1])
    if path.startswith("file://"):
        path = path[len("file://"):]
    parts = [p for p in path.rstrip("/").split("/") if p]
    if parts:
        last = parts[-1]
        if last.endswith(".app"):
            last = last[:-4]
        named = usable_name(last)
        if named:
            return named
    ident = it.get("identifier") or ""
    if "BackgroundActivityCheck" in ident:
        return "BackgroundActivityCheck"
    tail = ident.rsplit(".", 1)[-1] if "." in ident else ""
    named = usable_name(tail)
    if named and any(ch.isupper() for ch in named):
        return named
    return it.get("bundle") or it.get("id") or ident or "login item"


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
                "identifier": ident,
                "id": launchd_id(ident),
                "parent": s(r.get("container")),
                "name": s(r.get("name")),
                "developer": s(r.get("developerName")),
                "team": s(r.get("teamIdentifier")),
                "url": s(r.get("url")),
                "executable": s(r.get("executablePath")),
            }


def app_items(paths):
    for it in iter_items(paths):
        if it["type"] == TYPE_APP and it["bundle"]:
            yield it


def mdm_rules(base: Path | None) -> list[dict]:
    """Service Management rules pushed by MDM (Fleet), from the base store."""
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
        # The launchd label, the recorded name, and the raw identifier.
        # koi.security.* is stored as koi.security.mdm.plist and shown as
        # koi.security.mdm.sh.
        return any(
            text.startswith(v)
            for text in (it["id"], it.get("name") or "", it.get("identifier") or "")
            if text
        )
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
        elif it["team"] and any(r.get("team") == it["team"] for r in mdm):
            # Same developer as an MDM Service Management rule, but this item
            # is not named by one. Do not tell the user to turn it off.
            cls, detail = "unknown", "company-team"
        else:
            cls, detail = "unknown", ""
        fields = [cls, kind, display_name(it), it["developer"], it["team"], ident, detail]
        print("|".join(f.replace("|", "/") for f in fields))
    return 0


def _pipe(text: str) -> str:
    return str(text).replace("\n", " ").replace("|", "/")


def disposition_phrase(enabled: bool, allowed: bool) -> str:
    state = "enabled" if enabled else "disabled"
    allow = "allowed" if allowed else "not allowed"
    return f"{state}, {allow}"


def bits_state(disp: int) -> tuple[bool, str]:
    enabled = bool(disp & DISP_ENABLED)
    allowed = bool(disp & DISP_ALLOWED)
    ok = enabled and allowed
    return ok, disposition_phrase(enabled, allowed)


def words_state(words: list[str]) -> tuple[bool, str]:
    enabled = "enabled" in words
    allowed = False
    for index, word in enumerate(words):
        if word == "allowed" and (index == 0 or words[index - 1] != "not"):
            allowed = True
    return enabled and allowed, disposition_phrase(enabled, allowed)


def item_matches_label(it: dict, label: str) -> bool:
    if it.get("name") == label or display_name(it) == label:
        return True
    ident = it.get("identifier") or ""
    if ident == label or ident.endswith("." + label):
        return True
    for raw in (it.get("executable") or "", it.get("url") or ""):
        path = unquote(str(raw).split("|")[-1])
        if path.startswith("file://"):
            path = path[len("file://"):]
        base = os.path.basename(path.rstrip("/"))
        if base in (label, label + ".app"):
            return True
    return False


def karabiner_lines(states: dict[str, list[tuple[bool, str]]]) -> list[str]:
    """One line per required service. Other background items are ignored."""
    lines = []
    hand = (
        " System Settings → General → Login Items & Extensions →"
        " Allow in the Background. macconfig does not change this"
    )
    for label in KARABINER_BACKGROUND:
        found = states.get(label) or []
        if not found:
            lines.append(
                f"warn|{label}|{_pipe(label)} is not in the background items,"
                " so it is not enabled and allowed." + hand
            )
            continue
        bad = [phrase for ok, phrase in found if not ok]
        if bad:
            lines.append(
                f"warn|{label}|{_pipe(label)} is {_pipe(bad[0])}."
                " It needs to be enabled and allowed." + hand
            )
        else:
            lines.append(f"ok|{label}|{_pipe(label)} is enabled and allowed")
    return lines


def states_from_items(items: list[dict]) -> dict[str, list[tuple[bool, str]]]:
    found: dict[str, list[tuple[bool, str]]] = {}
    for it in items:
        disp = it.get("disposition")
        if not isinstance(disp, int):
            continue
        for label in KARABINER_BACKGROUND:
            if item_matches_label(it, label):
                found.setdefault(label, []).append(bits_state(disp))
    return found


def parse_dumpbtm(text: str) -> list[dict]:
    """Name and disposition words from `sfltool dumpbtm` text."""
    records = []
    chunks = re.split(r"(?m)^\s*#\d+\s*:", "\n" + text)
    for chunk in chunks:
        name_match = re.search(r"(?m)^\s*Name:\s*(.+?)\s*$", chunk)
        disp_match = re.search(r"(?m)^\s*Disposition:\s*\[([^\]]*)\]", chunk)
        if not name_match or not disp_match:
            continue
        words = re.findall(r"[A-Za-z]+", disp_match.group(1))
        records.append({"name": name_match.group(1).strip(), "words": words})
    return records


def states_from_dump(records: list[dict]) -> dict[str, list[tuple[bool, str]]]:
    found: dict[str, list[tuple[bool, str]]] = {}
    for record in records:
        name = record.get("name") or ""
        if name not in KARABINER_BACKGROUND:
            continue
        found.setdefault(name, []).append(words_state(record.get("words") or []))
    return found


def read_live_items() -> list[dict] | None:
    """BTM items, None when the database is not there, or raise PermissionError."""
    try:
        _base, paths = stores()
    except OSError as exc:
        if exc.errno in (errno.EPERM, errno.EACCES):
            raise PermissionError(exc.errno, exc.strerror, str(BTM_DIR)) from exc
        raise
    if not paths:
        return None
    return list(iter_items(paths))


def read_sfltool_dump() -> str:
    """`sfltool dumpbtm` text, or '' when it is missing, fails, or does not finish."""
    try:
        proc = subprocess.run(
            ["sfltool", "dumpbtm"],
            capture_output=True,
            text=True,
            timeout=8,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return (proc.stdout or "") + (proc.stderr or "")


def resolve_karabiner(read_items, read_dump) -> list[str]:
    """Prefer the BTM database. Fall back to dump text only when that cannot be read."""
    items = None
    try:
        items = read_items()
    except PermissionError:
        items = None
    if items is not None:
        return karabiner_lines(states_from_items(items))
    dump = read_dump() or ""
    records = parse_dumpbtm(dump) if dump else []
    if records:
        return karabiner_lines(states_from_dump(records))
    return [
        "info|-|Karabiner background items could not be read, so Allow in the"
        " Background stays by hand. macconfig does not change this"
    ]


def karabiner_cli(argv: list[str]) -> int:
    dump_path = ""
    if argv[:1] == ["--dump"]:
        if len(argv) != 2:
            print("usage: btm-login-items.py --karabiner --dump FILE", file=sys.stderr)
            return 64
        dump_path = argv[1]
    elif argv:
        print("usage: btm-login-items.py --karabiner [--dump FILE]", file=sys.stderr)
        return 64
    try:
        if dump_path:
            with open(dump_path, encoding="utf-8") as fh:
                text = fh.read()
            records = parse_dumpbtm(text)
            if records:
                lines = karabiner_lines(states_from_dump(records))
            else:
                lines = [
                    "info|-|Karabiner background items could not be read from"
                    " that dump, so Allow in the Background stays by hand."
                    " macconfig does not change this"
                ]
        else:
            lines = resolve_karabiner(read_live_items, read_sfltool_dump)
    except OSError as exc:
        lines = [
            "info|-|Karabiner background items could not be read"
            f" ({_pipe(exc)}), so Allow in the Background stays by hand."
            " macconfig does not change this"
        ]
    except Exception as exc:  # noqa: BLE001 - report, don't crash the check
        lines = [
            "info|-|Karabiner background items could not be read"
            f" ({_pipe(exc)}), so Allow in the Background stays by hand."
            " macconfig does not change this"
        ]
    print("\n".join(lines))
    return 0


def main() -> int:
    args = sys.argv[1:]
    if args[:1] == ["--karabiner"]:
        return karabiner_cli(args[1:])
    try:
        base, paths = stores()
        if not paths:
            print("btm=missing", file=sys.stderr)
            return 2
        if args[:1] == ["--audit"]:
            if len(args) != 2:
                print("usage: btm-login-items.py --audit ALLOWLIST", file=sys.stderr)
                return 64
            return audit(args[1], base, paths)
        items = list(app_items(paths))
        if not args:
            for it in items:
                print(f"{it['bundle']}|{it['disposition']}|{it['enabled']}|{display_name(it)}")
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
