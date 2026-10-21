#!/usr/bin/env python3
"""Compare Finder sidebar Favorites with lib/sidebar-favorites.list.

Reads com.apple.LSSharedFileList.FavoriteItems.sfl4, or .sfl3, or .sfl2,
under ~/Library/Application Support/com.apple.sharedfilelist/. The newest
file that exists is the one Finder is using. File favorites are the items
whose bookmark has a file path. Other sidebar rows (AirDrop and similar)
are left out of the comparison. A match is the same paths in the same
order. Names in the list are labels for messages. An item with no Name
is shown as the folder basename.

Nothing here writes the sidebar file. Rebuilding it from this script is not
reliable, and mysides is not a Homebrew formula or cask.

Commands (stdout):
  compare --list FILE [--sfl FILE]
      ok|message
      bad|message
      warn|message
      --sfl overrides the file looked up under $HOME.
  paths --list FILE
      name<TAB>expanded path, in list order
  urls --list FILE
      name<TAB>file:// address, in list order
"""
from __future__ import annotations

import argparse
import errno
import os
import plistlib
import struct
import sys
from plistlib import UID
from urllib.parse import quote, unquote, urlparse

FAVORITE_DIR = os.path.join(
    "Library", "Application Support", "com.apple.sharedfilelist"
)
FAVORITE_FILES = (
    "com.apple.LSSharedFileList.FavoriteItems.sfl4",
    "com.apple.LSSharedFileList.FavoriteItems.sfl3",
    "com.apple.LSSharedFileList.FavoriteItems.sfl2",
)
BMK_STRING = 0x0100
BMK_ARRAY = 0x0600
PATH_KEY = 0x1004
VOLUME_PATH_KEY = 0x2002


def load_desired(path: str) -> list[tuple[str, str]]:
    home = os.environ.get("HOME", "")
    rows: list[tuple[str, str]] = []
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.split("#", 1)[0].strip()
            if not line or "|" not in line:
                continue
            name, folder = line.split("|", 1)
            name = name.strip()
            folder = folder.strip().replace("@HOME@", home)
            if name and folder:
                rows.append((name, folder))
    return rows


def norm_path(url_or_path: str) -> str:
    raw = url_or_path.strip()
    if raw.startswith("file:"):
        path = unquote(urlparse(raw).path)
    else:
        path = os.path.expanduser(raw)
    if path != "/" and path.endswith("/"):
        path = path.rstrip("/")
    return path


def file_url(path: str) -> str:
    folder = norm_path(path)
    return "file://" + quote(folder, safe="/") + "/"


def tilde(path: str) -> str:
    home = os.environ.get("HOME", "")
    if home and (path == home or path.startswith(home + os.sep)):
        return "~" + path[len(home) :]
    return path


def favorite_file(home: str) -> str:
    base = os.path.join(home, FAVORITE_DIR)
    for name in FAVORITE_FILES:
        path = os.path.join(base, name)
        if os.path.isfile(path):
            return path
    return os.path.join(base, FAVORITE_FILES[0])


def deref(objects: list, value):
    if isinstance(value, int) and not isinstance(value, bool):
        value = objects[value]
    while isinstance(value, UID):
        value = objects[value.data]
    return value


def as_uid_list(objects: list, value) -> list:
    value = deref(objects, value) if isinstance(value, UID) else value
    if isinstance(value, dict) and "NS.objects" in value:
        return value["NS.objects"]
    if isinstance(value, list):
        return value
    raise TypeError(f"expected a list, got {type(value).__name__}")


def ns_pairs(objects: list, item: dict) -> list[tuple]:
    return list(
        zip(
            as_uid_list(objects, item["NS.keys"]),
            as_uid_list(objects, item["NS.objects"]),
        )
    )


def dict_get(objects: list, item, key: str):
    if not isinstance(item, dict):
        return None
    if "NS.keys" in item and "NS.objects" in item:
        for raw_key, raw_val in ns_pairs(objects, item):
            if deref(objects, raw_key) == key:
                return deref(objects, raw_val)
        return None
    if key in item:
        return deref(objects, item[key])
    return None


def _bookmark_item(data: bytes, hdrsize: int, offset: int, depth: int):
    if depth > 8:
        raise ValueError("bookmark nested too deep")
    pos = offset + hdrsize
    if pos < 0 or pos > len(data) - 8:
        raise ValueError("bookmark offset out of range")
    length, typecode = struct.unpack_from("<II", data, pos)
    end = pos + 8 + length
    if length < 0 or end > len(data):
        raise ValueError("bookmark item truncated")
    blob = data[pos + 8 : end]
    dtype = typecode & 0xFFFFFF00
    if dtype == BMK_STRING:
        return blob.decode("utf-8")
    if dtype == BMK_ARRAY:
        found = []
        if length % 4 != 0:
            raise ValueError("bookmark array length")
        for index in range(0, length, 4):
            (child,) = struct.unpack_from("<I", blob, index)
            found.append(_bookmark_item(data, hdrsize, child, depth + 1))
        return found
    return None


def bookmark_path(data: bytes) -> str | None:
    """File path from an in-memory bookmark, or None when it is not one."""
    if not isinstance(data, (bytes, bytearray)) or len(data) < 16:
        return None
    raw = bytes(data)
    if raw[:4] not in (b"book", b"alis"):
        return None
    try:
        magic, size, _dummy, hdrsize = struct.unpack_from("<4sIII", raw, 0)
        if magic not in (b"book", b"alis"):
            return None
        if hdrsize < 16 or hdrsize > size or size != len(raw) or hdrsize > len(raw) - 4:
            return None
        (tocoffset,) = struct.unpack_from("<I", raw, hdrsize)
        volume = None
        parts = None
        seen = 0
        while tocoffset and seen < 8:
            seen += 1
            tocbase = hdrsize + tocoffset
            if tocbase < 0 or tocbase + 20 > len(raw):
                return None
            _tocsize, tocmagic, _tocid, nexttoc, toccount = struct.unpack_from(
                "<IIIII", raw, tocbase
            )
            if tocmagic != 0xFFFFFFFE:
                break
            for index in range(toccount):
                entry = tocbase + 20 + 12 * index
                if entry + 12 > len(raw):
                    return None
                eid, eoffset, _edummy = struct.unpack_from("<III", raw, entry)
                if eid & 0x80000000:
                    eid = _bookmark_item(raw, hdrsize, eid & 0x7FFFFFFF, 0)
                value = _bookmark_item(raw, hdrsize, eoffset, 0)
                if eid == PATH_KEY:
                    parts = value
                elif eid == VOLUME_PATH_KEY and isinstance(value, str):
                    volume = value
            tocoffset = nexttoc
    except (ValueError, struct.error, UnicodeError):
        return None
    return join_bookmark_path(volume, parts)


def join_bookmark_path(volume, parts) -> str | None:
    if not isinstance(parts, list) or not parts:
        return None
    cleaned: list[str] = []
    for part in parts:
        if not isinstance(part, str) or not part.strip("/"):
            return None
        cleaned.append(part.strip("/"))
    vol = volume if isinstance(volume, str) and volume else "/"
    if vol != "/":
        vol = vol.rstrip("/")
    rel = "/".join(cleaned)
    if vol == "/":
        return "/" + rel
    return vol + "/" + rel


def read_favorites(path: str) -> tuple[str, object]:
    """('ok', [(name, path), ...]) or ('warn', message). File favorites only."""
    try:
        with open(path, "rb") as fh:
            plist = plistlib.load(fh)
    except OSError as exc:
        if exc.errno in (errno.EPERM, errno.EACCES):
            return (
                "warn",
                "can't read Finder Favorites (Full Disk Access) — "
                "System Settings → Privacy & Security → Full Disk Access",
            )
        if exc.errno == errno.ENOENT:
            return ("warn", f"Finder Favorites file is missing ({path})")
        return ("warn", f"can't read Finder Favorites ({exc.strerror})")
    except (plistlib.InvalidFileException, ValueError, TypeError) as exc:
        return ("warn", f"could not read Finder Favorites ({exc})")
    if not isinstance(plist, dict) or "$objects" not in plist:
        return ("warn", "could not read Finder Favorites (not a sidebar archive)")
    objects = plist["$objects"]
    if not isinstance(objects, list) or not objects:
        return ("warn", "could not read Finder Favorites (empty archive)")
    try:
        root_ref = UID(1)
        top = plist.get("$top")
        if isinstance(top, dict) and "root" in top:
            root_ref = top["root"]
        root = deref(objects, root_ref)
        items_ref = dict_get(objects, root, "items")
        if items_ref is None:
            return ("warn", "could not read Finder Favorites (no items)")
        item_refs = as_uid_list(objects, items_ref)
        found: list[tuple[str, str]] = []
        saw_item = False
        for item_ref in item_refs:
            item = deref(objects, item_ref)
            if not isinstance(item, dict):
                continue
            saw_item = True
            name = dict_get(objects, item, "Name")
            if not isinstance(name, str):
                name = ""
            path_value = bookmark_path(dict_get(objects, item, "Bookmark"))
            if path_value is None:
                continue
            found.append((name, norm_path(path_value)))
    except (TypeError, ValueError, IndexError, KeyError, struct.error) as exc:
        return ("warn", f"could not read Finder Favorites ({exc})")
    if saw_item and not found:
        return (
            "warn",
            "could not read paths from Finder Favorites — "
            "check the sidebar by hand",
        )
    return ("ok", found)


def item_label(name: str, path: str) -> str:
    """Name from the sidebar item, or the folder basename when Name is absent."""
    if name:
        return name
    folder = norm_path(path)
    return os.path.basename(folder) or folder or "(no name)"


def compare(desired: list[tuple[str, str]], actual: list[tuple[str, str]]) -> tuple[str, str]:
    """Match file favorites by path, in order. List names are message labels."""
    if not desired:
        return "warn", "sidebar favorites list is empty — Favorites were not checked"
    want = [(name, norm_path(path)) for name, path in desired]
    have_paths = [norm_path(path) for _name, path in actual]
    want_paths = [path for _name, path in want]
    if have_paths == want_paths:
        names = ", ".join(name for name, _path in want)
        return "ok", f"Finder Favorites match ({names})"
    have = ", ".join(
        f"{item_label(name, path)} ({tilde(norm_path(path))})" for name, path in actual
    ) or "(none)"
    need = ", ".join(f"{name} ({tilde(path)})" for name, path in want)
    return "bad", f"Favorites are {have}; want {need}"


def emit_status(status: str, message: str) -> None:
    text = message.replace("\n", " ").replace("|", "/")
    print(f"{status}|{text}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="sidebar-favorites.py", description=__doc__)
    parser.add_argument("command", choices=("compare", "paths", "urls"))
    parser.add_argument("--list", default="", help="lib/sidebar-favorites.list")
    parser.add_argument("--sfl", default="", help="FavoriteItems.sfl2/3/4 to read")
    args = parser.parse_args(argv)
    try:
        if not args.list:
            emit_status("warn", "sidebar favorites list path is missing")
            return 0
        desired = load_desired(args.list)
        if args.command == "paths":
            for name, path in desired:
                print(f"{name}\t{norm_path(path)}")
            return 0
        if args.command == "urls":
            for name, path in desired:
                print(f"{name}\t{file_url(path)}")
            return 0
        path = args.sfl or favorite_file(os.environ.get("HOME", ""))
        if not args.sfl and not os.path.isfile(path):
            emit_status("warn", f"Finder Favorites file is missing ({path})")
            return 0
        status, payload = read_favorites(path)
        if status != "ok" or not isinstance(payload, list):
            emit_status("warn", str(payload))
            return 0
        status, message = compare(desired, payload)
        emit_status(status, message)
        return 0
    except Exception as exc:  # noqa: BLE001 - report, don't crash macos.sh
        emit_status("warn", f"could not compare Finder Favorites ({exc})")
        return 0


if __name__ == "__main__":
    sys.exit(main())
