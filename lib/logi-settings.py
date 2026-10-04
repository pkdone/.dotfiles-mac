#!/usr/bin/env python3
"""Read-only check of Logi Options+ settings against lib/logi-expected.list.

Usage: logi-settings.py [--db PATH] [--expected FILE] [--only ID[,ID...]]

Copies settings.db (+ its -wal / -shm, which hold recent changes) into a private temp
dir, opens the COPY read-only, and deletes it afterwards. The real database is never
opened, locked or written. The device is found by model id (ever_connected_devices),
never by serial number.

Output, one line per result:  status|id|message
  ok | drift | warn   one per checked id (severity from the expected-values file)
  error               the app data is missing or its format is unreadable
Exit status: 0 all ok, 1 some drift / warn, 2 unreadable (format, bad --only id),
3 settings.db not found.
"""
import json
import os
import shutil
import sqlite3
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DB = os.path.expanduser(
    "~/Library/Application Support/LogiOptionsPlus/settings.db")
DEFAULT_EXPECTED = os.path.join(HERE, "logi-expected.list")
MISSING = object()


def out(status, ident, msg):
    print("%s|%s|%s" % (status, ident or "-", str(msg).replace("\n", " ").replace("|", "/")))


def load_expected(path):
    model, name, rows = None, None, []
    with open(path) as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            f = [x.strip() for x in line.split("|")]
            if f[0] == "model" and len(f) >= 2:
                model = f[1]
                name = f[2] if len(f) > 2 and f[2] else f[1]
                continue
            if len(f) != 9:
                raise ValueError("bad row in %s: %s" % (os.path.basename(path), line))
            keys = ("id", "scope", "where", "path", "type", "expected", "tol", "severity", "label")
            row = dict(zip(keys, f))
            if row["scope"] not in ("slot", "global") or row["type"] not in ("str", "bool", "num") \
                    or row["severity"] not in ("drift", "warn"):
                raise ValueError("bad row in %s: %s" % (os.path.basename(path), line))
            rows.append(row)
    if not model:
        raise ValueError("no 'model|…' line in %s" % os.path.basename(path))
    return model, name, rows


def read_copy(db):
    """Return the settings dict read from a temp copy of db."""
    tmp = tempfile.mkdtemp(prefix="logi-settings.")
    try:
        os.chmod(tmp, 0o700)
        copy = os.path.join(tmp, "settings.db")
        for suffix in ("", "-wal", "-shm"):
            if os.path.isfile(db + suffix):
                shutil.copyfile(db + suffix, copy + suffix)
        try:
            con = sqlite3.connect("file:%s?mode=ro" % copy, uri=True, timeout=5)
        except sqlite3.Error:
            con = sqlite3.connect(copy, timeout=5)   # the copy, never the real file
        try:
            row = con.execute("SELECT file FROM data LIMIT 1").fetchone()
        finally:
            con.close()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if not row or row[0] is None:
        raise ValueError("table 'data' is empty")
    blob = row[0]
    if isinstance(blob, (bytes, bytearray, memoryview)):
        blob = bytes(blob).decode("utf-8")
    data = json.loads(blob)
    if not isinstance(data, dict):
        raise ValueError("settings JSON is not an object")
    return data


def dig(obj, path):
    for key in path.split("."):
        if isinstance(obj, dict) and key in obj:
            obj = obj[key]
        else:
            return MISSING
    return obj


def slot_prefix(data, model):
    devs = dig(data, "ever_connected_devices.devices")
    if isinstance(devs, list):
        for d in devs:
            if isinstance(d, dict) and str(d.get("deviceModel", "")).lower() == model.lower() \
                    and d.get("slotPrefix"):
                return d["slotPrefix"]
    return None


def default_profile(data):
    keys = data.get("profile_keys")
    if not isinstance(keys, list):
        keys = [k for k in data if k.startswith("profile-")]
    profiles = [data[k] for k in keys if isinstance(data.get(k), dict)]
    for p in profiles:
        if p.get("name") == "PROFILE_NAME_DEFAULT":
            return p
    return profiles[0] if profiles else None


def find_assignment(profile, prefix, model, where):
    found = None
    for a in profile.get("assignments") or []:
        sid = str(a.get("slotId", "")) if isinstance(a, dict) else ""
        if prefix and sid == "%s_%s" % (prefix, where):
            return a
        # fallback when the device list lacks the model: slot ids embed it (…-2b034_c195)
        if not prefix and sid.endswith("-%s_%s" % (model, where)):
            found = a
    return found


def show(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is MISSING:
        return "missing"
    if isinstance(v, float):
        return ("%.4f" % v).rstrip("0").rstrip(".")
    return str(v)


def compare(row, actual):
    t, want = row["type"], row["expected"]
    if actual is MISSING:
        return False
    if t == "bool":
        return isinstance(actual, bool) and actual == (want.lower() == "true")
    if t == "num":
        if isinstance(actual, bool) or not isinstance(actual, (int, float)):
            return False
        return abs(float(actual) - float(want)) <= float(row["tol"] or 0)
    return str(actual) == want


def main(argv):
    db, expected, only = DEFAULT_DB, DEFAULT_EXPECTED, None
    args = list(argv)
    while args:
        a = args.pop(0)
        if a in ("--db", "--expected", "--only") and args:
            v = args.pop(0)
            if a == "--db":
                db = v
            elif a == "--expected":
                expected = v
            else:
                only = [x for x in v.split(",") if x]
        else:
            out("error", "", "usage: logi-settings.py [--db PATH] [--expected FILE] [--only ID,…]")
            return 2
    try:
        model, name, rows = load_expected(expected)
    except (OSError, ValueError) as e:
        out("error", "", "expected-values file unreadable: %s" % e)
        return 2
    if only is not None:
        unknown = [i for i in only if i not in [r["id"] for r in rows]]
        if unknown:
            out("error", "", "unknown id(s) %s (not in %s)" % (",".join(unknown), os.path.basename(expected)))
            return 2
        rows = [r for r in rows if r["id"] in only]
    if not os.path.isfile(db):
        out("error", "", "settings.db not found (%s) — open Logi Options+ once" % db.replace(os.path.expanduser("~"), "~"))
        return 3
    try:
        data = read_copy(db)
    except (OSError, sqlite3.Error, ValueError, UnicodeDecodeError) as e:
        out("error", "", "settings.db unreadable (format changed?): %s" % e)
        return 2

    prefix = slot_prefix(data, model)
    profile = default_profile(data)
    rc = 0
    for r in rows:
        if r["scope"] == "global":
            actual = dig(data, r["path"].replace("{model}", model))
        else:
            if profile is None:
                out("error", r["id"], "no profile found in settings.db (format changed?)")
                rc = 2
                continue
            a = find_assignment(profile, prefix, model, r["where"])
            if a is None:
                status = "error" if prefix is None else r["severity"]
                out(status, r["id"], "%s: %s (model %s) not found in the default profile" % (r["label"], name, model))
                rc = max(rc, 2 if status == "error" else 1)
                continue
            actual = dig(a, r["path"])
        if compare(r, actual):
            out("ok", r["id"], "%s (%s)" % (r["label"], show(actual)))
        else:
            want = r["expected"] + (" ±%s" % r["tol"] if r["tol"] else "")
            out(r["severity"], r["id"], "%s — expected %s, found %s" % (r["label"], want, show(actual)))
            rc = max(rc, 1)
    return rc


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:  # never crash the caller: report as unreadable
        out("error", "", "logi-settings.py failed: %s: %s" % (type(e).__name__, e))
        sys.exit(2)
