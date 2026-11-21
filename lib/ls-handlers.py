#!/usr/bin/env python3
"""Check and apply lib/ls-handlers.list: Launch Services defaults duti can't set.

Reads LSHandlers from com.apple.launchservices.secure (or the plist named by
LS_HANDLERS_PLIST, for tests). Output lines are `status|key|message` with status
ok, bad, chg, dry, or fail, as lib/file-handlers.py prints them.

  ls-handlers.py [LIST]                  check, read-only
  ls-handlers.py --apply [--dry-run] [LIST]
"""
import os
import plistlib
import re
import subprocess
import sys

DOMAIN = "com.apple.LaunchServices/com.apple.launchservices.secure"
HERE = os.path.dirname(os.path.abspath(__file__))
KEY_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._+-]*")
BUNDLE_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9.-]*")
BLOCKED = {"public.html", "public.xhtml", "html", "htm", "xhtml"}


def load_rows(path):
    rows = []
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            raw = line.strip()
            if not raw or raw.startswith("#"):
                continue
            p = [x.strip() for x in raw.split("|")]
            if len(p) != 4 or p[0] not in ("uti", "ext"):
                raise ValueError(f"line {n}: want kind|key|app|bundle-id with kind uti or ext")
            kind, key, app, bundle = p
            key = key.lower() if kind == "ext" else key
            if not KEY_RE.fullmatch(key) or not BUNDLE_RE.fullmatch(bundle):
                raise ValueError(f"line {n}: bad key or bundle id")
            if key.lower() in BLOCKED:
                raise ValueError(f"line {n}: {key} is tied to the default browser")
            rows.append((kind, key, app, bundle))
    return rows


def read_handlers():
    src = os.environ.get("LS_HANDLERS_PLIST")
    if src:
        data = open(src, "rb").read() if os.path.exists(src) else b""
    else:
        try:
            r = subprocess.run(["defaults", "export", DOMAIN, "-"], capture_output=True)
            data = r.stdout if r.returncode == 0 else b""
        except OSError:
            data = b""
    if not data:
        return []
    return plistlib.loads(data).get("LSHandlers", [])


def current(handlers, kind, key):
    """Role-all bundle of the last matching LSHandlers entry, lower-cased."""
    have = ""
    for h in handlers:
        if kind == "uti":
            hit = str(h.get("LSHandlerContentType", "")).lower() == key.lower()
        else:
            hit = (h.get("LSHandlerContentTagClass") == "public.filename-extension"
                   and str(h.get("LSHandlerContentTag", "")).lower() == key)
        if hit:
            have = str(h.get("LSHandlerRoleAll") or h.get("LSHandlerRoleViewer") or "")
    return have


def entry_args(kind, key, bundle):
    if kind == "uti":
        return ("{LSHandlerContentType=\"%s\";LSHandlerRoleAll=\"%s\";"
                "LSHandlerRoleEditor=\"%s\";LSHandlerRoleViewer=\"%s\";}"
                % (key, bundle, bundle, bundle))
    return ("{LSHandlerContentTag=\"%s\";LSHandlerContentTagClass=\"public.filename-extension\";"
            "LSHandlerRoleAll=\"%s\";}" % (key, bundle))


def main(argv):
    apply = "--apply" in argv
    dry = "--dry-run" in argv
    args = [a for a in argv if not a.startswith("--")]
    path = args[0] if args else os.path.join(HERE, "ls-handlers.list")
    try:
        rows = load_rows(path)
    except (OSError, ValueError) as exc:
        print(f"fail||could not read the Launch Services list ({exc})")
        return 1
    handlers = read_handlers()
    rc = 0
    changed = False
    for kind, key, app, bundle in rows:
        have = current(handlers, kind, key)
        name = key if kind == "uti" else f".{key}"
        want = f"{app} / {bundle}"
        if have.lower() == bundle.lower():
            print(f"ok|{key}|{name} -> {want}")
            continue
        shown = have or "unset"
        if not apply:
            print(f"bad|{key}|{name} -> {shown} (expected {want})")
        elif dry:
            print(f"dry|{key}|{name}: {shown} -> {want}")
        else:
            try:
                r = subprocess.run(["defaults", "write", DOMAIN, "LSHandlers", "-array-add",
                                    entry_args(kind, key, bundle)], capture_output=True, text=True)
                err = "" if r.returncode == 0 else r.stderr.strip() or "failed"
            except OSError as exc:
                err = str(exc)
            if err:
                print(f"fail|{key}|{name}: defaults write failed: {err}")
                rc = 1
            else:
                print(f"chg|{key}|{name}: {shown} -> {want}")
                changed = True
    if changed:
        try:
            subprocess.run(["killall", "lsd"], capture_output=True)
        except OSError:
            pass
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
