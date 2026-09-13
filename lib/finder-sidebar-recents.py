#!/usr/bin/env python3
"""Check/apply Finder sidebar Recents: TopSidebarSection ItemIsHidden=True."""
from __future__ import annotations

import argparse
import errno
import os
import re
import sys
from plistlib import FMT_BINARY, UID, dumps, load

SFL = os.path.expanduser(
    "~/Library/Application Support/com.apple.sharedfilelist/"
    "com.apple.LSSharedFileList.TopSidebarSection.sfl4"
)
FAV_CANDIDATES = [
    os.path.expanduser(
        "~/Library/Application Support/com.apple.sharedfilelist/"
        f"com.apple.LSSharedFileList.FavoriteItems.{ext}"
    )
    for ext in ("sfl2", "sfl3", "sfl4")
]
HIDDEN_KEY = "com.apple.LSSharedFileList.ItemIsHidden"


def deref(objects, x):
    # Bare ints are $objects indices (root is often passed as 1).
    if isinstance(x, int) and not isinstance(x, bool):
        x = objects[x]
    while isinstance(x, UID):
        x = objects[x.data]
    return x


def as_uid_list(objects, x):
    x = deref(objects, x) if isinstance(x, UID) else x
    if isinstance(x, dict) and "NS.objects" in x:
        return x["NS.objects"]
    if isinstance(x, list):
        return x
    raise TypeError(f"expected UID list, got {type(x)}")


def ns_dict_pairs(objects, d):
    return list(zip(as_uid_list(objects, d["NS.keys"]), as_uid_list(objects, d["NS.objects"])))


def bookmark_is_recents(bm: bytes) -> bool:
    return b"Recents" in bm and (
        b"myDocuments.cannedSearch" in bm or b"cannedSearch" in bm
    )


def find_recents_item(objects):
    root = deref(objects, 1)
    items_ref = None
    for kr, vr in ns_dict_pairs(objects, root):
        if deref(objects, kr) == "items":
            items_ref = vr
            break
    if items_ref is None:
        return None
    item_refs = as_uid_list(objects, items_ref)
    for iref in item_refs:
        d = deref(objects, iref)
        for kr, vr in ns_dict_pairs(objects, d):
            if deref(objects, kr) != "Bookmark":
                continue
            bm = deref(objects, vr)
            if isinstance(bm, (bytes, bytearray)) and bookmark_is_recents(bytes(bm)):
                return iref
    return None


def get_hidden(objects, item_ref):
    d = deref(objects, item_ref)
    for kr, vr in ns_dict_pairs(objects, d):
        if deref(objects, kr) != "CustomItemProperties":
            continue
        props = deref(objects, vr)
        if not isinstance(props, dict) or "NS.keys" not in props:
            return None
        for pkr, pvr in ns_dict_pairs(objects, props):
            if deref(objects, pkr) == HIDDEN_KEY:
                return bool(deref(objects, pvr))
    return None


def set_hidden(objects, item_ref, value: bool) -> bool:
    d = deref(objects, item_ref)
    for kr, vr in ns_dict_pairs(objects, d):
        if deref(objects, kr) != "CustomItemProperties":
            continue
        props = deref(objects, vr)
        if not isinstance(props, dict) or "NS.keys" not in props:
            return False
        for pkr, pvr in ns_dict_pairs(objects, props):
            if deref(objects, pkr) == HIDDEN_KEY:
                if isinstance(pvr, UID):
                    if bool(objects[pvr.data]) == value:
                        return False
                    objects[pvr.data] = value
                    return True
                return False
        # Key missing — append string + bool into $objects
        key_idx = len(objects)
        objects.append(HIDDEN_KEY)
        val_idx = len(objects)
        objects.append(value)
        keys = as_uid_list(objects, props["NS.keys"])
        vals = as_uid_list(objects, props["NS.objects"])
        # If NS.keys was inline list on props, mutate that list
        if isinstance(props["NS.keys"], list):
            props["NS.keys"].append(UID(key_idx))
            props["NS.objects"].append(UID(val_idx))
        else:
            keys.append(UID(key_idx))
            vals.append(UID(val_idx))
        return True
    return False


def favorite_has_recents() -> bool:
    for path in FAV_CANDIDATES:
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as f:
            raw = f.read()
        try:
            pl = load(open(path, "rb"))
        except Exception:
            continue
        objects = pl["$objects"]
        for o in objects:
            if isinstance(o, str) and o == "Recents":
                return True
            if isinstance(o, (bytes, bytearray)):
                # canned Recents in favorites would be unusual; look for display name
                if re.search(rb"(^|/)Recents(\x00|$)", bytes(o)):
                    return True
                strs = [s.decode() for s in re.findall(rb"[\x20-\x7e]{3,}", bytes(o))]
                if "Recents" in strs and any("cannedSearch" in s for s in strs):
                    return True
    return False


def _tcc_denied(exc: OSError) -> int:
    print(f"tcc=denied path={exc.filename or SFL}", file=sys.stderr)
    return 3


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    try:
        if not os.path.isfile(SFL):
            print("missing TopSidebarSection.sfl4", file=sys.stderr)
            return 2
        with open(SFL, "rb") as f:
            pl = load(f)
    except OSError as e:
        if e.errno in (errno.EPERM, errno.EACCES):
            return _tcc_denied(e)
        raise
    objects = pl["$objects"]
    iref = find_recents_item(objects)
    fav = favorite_has_recents()
    if iref is None:
        print("recents_item=missing")
        status = "ok"
    else:
        hidden = get_hidden(objects, iref)
        if hidden is True:
            print("recents_item=hidden")
            status = "ok"
        elif hidden is False:
            print("recents_item=visible")
            status = "visible"
        else:
            print("recents_item=unknown_props")
            status = "unknown"
    print("favorite_items=" + ("has_recents" if fav else "no_recents"))
    if args.apply:
        if status in ("visible", "unknown") and iref is not None:
            if set_hidden(objects, iref, True):
                try:
                    with open(SFL, "wb") as f:
                        f.write(dumps(pl, fmt=FMT_BINARY))
                except OSError as e:
                    if e.errno in (errno.EPERM, errno.EACCES):
                        return _tcc_denied(e)
                    raise
                print("applied=hidden")
            else:
                print("applied=failed", file=sys.stderr)
                return 1
        else:
            print("applied=already_ok")
        return 1 if fav else 0
    if fav or status != "ok":
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
