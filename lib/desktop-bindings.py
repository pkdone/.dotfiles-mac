#!/usr/bin/env python3
"""Compare and apply Dock "Assign To" desktop pins against lib/desktop-bindings.list.

Check (the default) is read-only. One line per app, fields separated by `|`:

    ok|bundle|message
    bad|bundle|message
    warn||message

macOS stores pins in com.apple.spaces `app-bindings` (bundle id -> Space UUID).
Desktop N is the Nth normal Space (type 0) on the Main display; full-screen
Spaces are skipped. A binding of "" is Desktop 1 when that Space's UUID is
empty. A missing key is "None".

`--apply` writes the list back through the same map, resolved at apply time
(UUIDs for Desktops 2+ change if Spaces are recreated). `none` deletes the
key. Other `app-bindings` entries are kept. Spaces are never created or
reordered. The domain is backed up, then `defaults write ... -dict` replaces
`app-bindings` (that is how a key is removed), and Dock is restarted only if
a pin changed.

`--plist` / `--out` read and write a plist file instead of `defaults`, so
this can be tested with no Dock. `DESKTOP_BINDINGS_BACKUP_DIR` overrides the
backup directory.
"""
from __future__ import annotations

import argparse
import os
import plistlib
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOMAIN = "com.apple.spaces"
BINDINGS = "app-bindings"


def emit(status: str, bundle: str, message: str) -> None:
    text = str(message).replace("\n", " ").replace("|", "/")
    print(f"{status}|{bundle}|{text}")


def load_rows(path: str) -> list[tuple[str, str, str]]:
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            name, bundle, want = (p.strip() for p in line.split("|"))
            rows.append((name, bundle, want))
    return rows


def load_prefs(path: str) -> dict:
    if path:
        with open(path, "rb") as fh:
            return plistlib.load(fh)
    proc = subprocess.run(
        ["defaults", "export", DOMAIN, "-"], capture_output=True, check=False)
    if proc.returncode != 0:
        err = (proc.stderr or b"").decode("utf-8", "replace").strip() or "defaults export failed"
        raise RuntimeError(err)
    return plistlib.loads(proc.stdout)


def main_desktops(prefs: dict) -> list:
    """Normal Spaces on the Main display, in order. Full-screen Spaces are skipped."""
    monitors = (prefs.get("SpacesDisplayConfiguration", {})
                .get("Management Data", {}).get("Monitors", []))
    main_mon = next((m for m in monitors if m.get("Display Identifier") == "Main"), None)
    if main_mon is None:
        main_mon = next((m for m in monitors if m.get("Spaces")), {})
    return [s for s in main_mon.get("Spaces", []) if s.get("type", 0) == 0]


def desktop_maps(desktops: list) -> tuple[dict, dict]:
    """Same UUID → Desktop N map the checker uses, plus its inverse for writes."""
    uuid_to_n: dict = {}
    n_to_uuid: dict = {}
    for i, space in enumerate(desktops, 1):
        uuid = space.get("uuid") or ""
        uuid_to_n[uuid] = i
        n_to_uuid[i] = uuid
    return uuid_to_n, n_to_uuid


def lowered_bindings(raw) -> dict:
    return {k.lower(): v for k, v in (raw or {}).items()}


def have_desktop(lowered: dict, uuid_to_n: dict, bundle: str) -> str:
    key = bundle.lower()
    if key not in lowered:
        return "none"
    val = lowered[key]
    n = uuid_to_n.get(val or "")
    if n:
        return str(n)
    return f"unknown desktop {val or '(empty)'}"


def label(desktop: str) -> str:
    return "None" if desktop == "none" else f"Desktop {desktop}"


def check_rows(prefs: dict, rows: list[tuple[str, str, str]]) -> list[tuple[str, str, str]]:
    lowered = lowered_bindings(prefs.get(BINDINGS) or {})
    uuid_to_n, _n_to_uuid = desktop_maps(main_desktops(prefs))
    out = []
    for name, bundle, want in rows:
        have = have_desktop(lowered, uuid_to_n, bundle)
        if have == want:
            out.append(("ok", bundle, f"{name} assigned to {label(want)}"))
        else:
            shown = have if have.startswith("unknown") else label(have)
            out.append(("bad", bundle, f"{name} assigned to {shown} (expected {label(want)})"))
    return out


def plan(prefs: dict, rows, tokens: list[str], dry_run: bool):
    """Return (plans, raw bindings). Each plan is (status, bundle, message, op)."""
    raw = prefs.get(BINDINGS) or {}
    if not isinstance(raw, dict):
        raise TypeError("app-bindings is not a dict")
    lowered = lowered_bindings(raw)
    desktops = main_desktops(prefs)
    uuid_to_n, n_to_uuid = desktop_maps(desktops)
    selected = {t.lower() for t in tokens}
    plans = []
    seen = set()
    for name, bundle, want in rows:
        if selected and bundle.lower() not in selected:
            continue
        seen.add(bundle.lower())
        have = have_desktop(lowered, uuid_to_n, bundle)
        if have == want:
            plans.append(("ok", bundle, f"{name} already assigned to {label(want)}", None))
            continue
        if want == "none":
            verb = "would clear" if dry_run else "clear"
            plans.append(("dry" if dry_run else "chg", bundle, f"{verb} {name} (None)", ("delete",)))
            continue
        if not want.isdigit() or int(want) < 1:
            plans.append(("refuse", bundle, f"{name}: desktop {want!r} is not 1..N or none", None))
            continue
        n = int(want)
        if n not in n_to_uuid:
            # Not a failed write: there is no Space to point at, and we don't create one.
            plans.append((
                "refuse", bundle,
                f"{name}: Desktop {n} doesn't exist on the Main display (have {len(n_to_uuid)})",
                None))
            continue
        uuid = n_to_uuid[n]
        if not isinstance(uuid, str):
            plans.append(("refuse", bundle, f"{name}: Desktop {n} UUID is not a string", None))
            continue
        verb = "would assign" if dry_run else "assign"
        where = f"Desktop {n}" if uuid == "" else f"Desktop {n} ({uuid})"
        plans.append((
            "dry" if dry_run else "chg", bundle,
            f"{verb} {name} to {where}", ("set", uuid)))
    for token in tokens:
        if token.lower() not in seen:
            plans.append(("refuse", token, "not in lib/desktop-bindings.list", None))
    return plans, raw


def new_bindings(raw: dict, plans) -> dict:
    """Copy of app-bindings with planned sets/deletes applied. Unmanaged keys stay.

    Managed keys are dropped (every case variant) and then reapplied in list
    order, so a later `none` removes a key an earlier row set.
    """
    managed = {bundle.lower() for status, bundle, _msg, op in plans if status == "chg" and op}
    updated = {}
    for key, val in raw.items():
        if not isinstance(key, str):
            raise TypeError(f"app-bindings key {key!r} is not a string")
        if key.lower() in managed:
            continue
        if not isinstance(val, str):
            raise TypeError(f"app-bindings {key!r} value is {type(val).__name__}, not a string")
        updated[key] = val
    for status, bundle, _msg, op in plans:
        if status != "chg" or not op:
            continue
        key = bundle.lower()
        if op[0] == "set":
            updated[key] = op[1]
        else:
            updated.pop(key, None)
    return updated


def defaults_write_argv(bindings: dict) -> list[str]:
    # `-dict` replaces the whole dictionary, which is what deletes a key.
    # `-dict-add` can only insert. Unmanaged keys are included so they survive.
    if not bindings:
        return ["defaults", "delete", DOMAIN, BINDINGS]
    argv = ["defaults", "write", DOMAIN, BINDINGS, "-dict"]
    for key, val in bindings.items():
        argv.extend((key, val))
    return argv


def run_defaults(argv: list[str]) -> None:
    proc = subprocess.run(argv, capture_output=True, check=False)
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or b"").decode("utf-8", "replace").strip()
        raise RuntimeError(err or "defaults failed")


def backup_spaces() -> str:
    root = os.environ.get("DESKTOP_BINDINGS_BACKUP_DIR") or os.path.join(ROOT, "backups")
    dest_dir = os.path.join(root, time.strftime("defaults-%Y%m%d-%H%M%S"))
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, f"{DOMAIN}.plist")
    run_defaults(["defaults", "export", DOMAIN, dest])
    return dest


def write_out(prefs: dict, bindings: dict, path: str) -> None:
    updated = dict(prefs)
    updated[BINDINGS] = bindings
    with open(path, "wb") as fh:
        plistlib.dump(updated, fh, fmt=plistlib.FMT_XML)


def restart_dock() -> str:
    proc = subprocess.run(["killall", "Dock"], capture_output=True, check=False)
    if proc.returncode == 0:
        return "restarted Dock"
    return "Dock not running"


def fail_changes(plans, message: str) -> int:
    for status, bundle, _msg, _op in plans:
        if status == "chg":
            emit("fail", bundle, message)
        else:
            emit(status, bundle, _msg)
    return 1


def apply_plans(prefs: dict, plans, raw: dict, args) -> int:
    changes = [p for p in plans if p[0] == "chg"]
    if changes:
        try:
            updated = new_bindings(raw, plans)
        except Exception as exc:  # noqa: BLE001 - report, don't crash check.sh
            return fail_changes(plans, f"not written ({exc})")
        if args.out:
            try:
                write_out(prefs, updated, args.out)
            except Exception as exc:  # noqa: BLE001
                return fail_changes(plans, f"not written ({exc})")
        elif args.plist:
            return fail_changes(
                plans, "refusing to write live preferences from --plist (pass --out)")
        else:
            try:
                backed_up = backup_spaces()
                run_defaults(defaults_write_argv(updated))
            except Exception as exc:  # noqa: BLE001
                return fail_changes(plans, f"not written ({exc})")
            emit("note", "", f"backed up com.apple.spaces -> {backed_up}")
            emit("note", "", restart_dock())
    for status, bundle, message, _op in plans:
        emit(status, bundle, message)
    if any(p[0] in ("fail", "refuse") for p in plans):
        return 1
    return 0


def report_unreadable(args, exc: Exception) -> int:
    message = f"could not read com.apple.spaces ({exc})"
    if not args.apply:
        emit("warn", "", message)
        return 0
    tokens = [t.strip() for t in args.only.split(",") if t.strip()] if args.only else []
    if tokens:
        for token in tokens:
            emit("fail", token, message)
    else:
        emit("fail", "", message)
    return 2


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="desktop-bindings.py", description=__doc__)
    parser.add_argument("list_path", help="pipe-delimited name|bundle|desktop list")
    parser.add_argument("--apply", action="store_true", help="write app-bindings from the list")
    parser.add_argument("--dry-run", action="store_true", help="with --apply, change nothing")
    parser.add_argument("--only", default="", help="comma-separated bundle ids to apply")
    parser.add_argument("--plist", default="", help="read this plist instead of defaults export")
    parser.add_argument("--out", default="", help="with --apply, write the plist here instead of defaults")
    args = parser.parse_args(argv)
    if args.dry_run:
        args.apply = True
    try:
        prefs = load_prefs(args.plist)
    except Exception as exc:  # noqa: BLE001
        return report_unreadable(args, exc)
    rows = load_rows(args.list_path)
    if not args.apply:
        for status, bundle, message in check_rows(prefs, rows):
            emit(status, bundle, message)
        return 0
    tokens = [t.strip() for t in args.only.split(",") if t.strip()] if args.only else []
    try:
        plans, raw = plan(prefs, rows, tokens, args.dry_run)
    except Exception as exc:  # noqa: BLE001
        return report_unreadable(args, exc)
    return apply_plans(prefs, plans, raw, args)


if __name__ == "__main__":
    sys.exit(main())
