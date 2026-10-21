#!/usr/bin/env python3
"""Check Finder sidebar rows that the sidebar files name.

Reads the same shared-file-list archives as lib/sidebar-favorites.py
(Name, Bookmark, and com.apple.LSSharedFileList.ItemIsHidden). The files are:

    ~/Library/Application Support/com.apple.sharedfilelist/
        com.apple.LSSharedFileList.TopSidebarSection.sfl4
        com.apple.LSSharedFileList.FavoriteVolumes.sfl4

sfl4 is preferred. sfl3, then sfl2, is used when sfl4 is not there.
lib/finder-sidebar-rows.list is what each named row should be.

A row is hidden only when ItemIsHidden is true. No such property means the
row is showing. A row this check cannot name stays by hand (one info line).
Nothing here writes a sidebar file.

The Tags group collapsed is SidebarTagsSctionDisclosedState in
lib/macos-defaults.list (Apple spells it that way). Recents hidden is
lib/finder-sidebar-recents.py. This script does not repeat those.

ShowRecentTags and SidebarShowingiCloudDesktop are not checked. Their
values on this Mac were not confirmed, so pinning them would warn on a
good setup.

Output, one line per result, fields separated by |:

    ok|id|message
    warn|id|message
    info|id|message
"""
from __future__ import annotations

import argparse
import errno
import importlib.util
import os
import plistlib
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_LIST = os.path.join(HERE, "finder-sidebar-rows.list")
SIDEBAR_DIR = os.path.join(
    "Library", "Application Support", "com.apple.sharedfilelist"
)
TOP_NAMES = tuple(
    f"com.apple.LSSharedFileList.TopSidebarSection.{ext}"
    for ext in ("sfl4", "sfl3", "sfl2")
)
VOLUME_NAMES = tuple(
    f"com.apple.LSSharedFileList.FavoriteVolumes.{ext}"
    for ext in ("sfl4", "sfl3", "sfl2")
)
HIDDEN_KEY = "com.apple.LSSharedFileList.ItemIsHidden"
TITLES = {
    "shared": "Shared",
    "airdrop": "AirDrop",
    "icloud": "iCloud Drive",
    "home": "your home folder",
    "macintosh-hd": "Macintosh HD",
    "network": "Network",
    "trash": "Trash",
}
FIX = " macconfig does not change the sidebar"


def emit(status: str, ident: str, message: str) -> None:
    text = str(message).replace("\n", " ").replace("|", "/")
    name = (ident or "-").replace("|", "/").replace("\n", " ")
    print(f"{status}|{name}|{text}")


def load_reader():
    path = os.path.join(HERE, "sidebar-favorites.py")
    spec = importlib.util.spec_from_file_location("sidebar_favorites_reader", path)
    if spec is None or spec.loader is None:
        raise ImportError(path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_rules(path: str) -> list[tuple[str, str, str]]:
    rules: list[tuple[str, str, str]] = []
    where_ok = {"top", "volumes", "either"}
    want_ok = {"hidden", "visible", "first"}
    with open(path, encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            parts = [part.strip() for part in line.split("|")]
            if len(parts) != 3 or not parts[0]:
                raise ValueError(f"finder-sidebar-rows.list:{lineno}: expected id, where, want")
            ident, where, want = parts
            if where not in where_ok or want not in want_ok:
                raise ValueError(
                    f"finder-sidebar-rows.list:{lineno}: where is top, volumes,"
                    " or either; want is hidden, visible, or first"
                )
            rules.append((ident, where, want))
    if not rules:
        raise ValueError("finder-sidebar-rows.list has no rows")
    return rules


def existing_file(directory: str, names: tuple[str, ...]) -> str:
    for name in names:
        path = os.path.join(directory, name)
        if os.path.isfile(path):
            return path
    return os.path.join(directory, names[0])


def as_hidden(value: object) -> bool | None:
    if isinstance(value, bool):
        return value
    if type(value) is int and value in (0, 1):
        return bool(value)
    return None


def bookmark_strings(data: object) -> list[str]:
    if not isinstance(data, (bytes, bytearray)):
        return []
    return [item.decode("ascii") for item in re.findall(rb"[\x20-\x7e]{3,}", bytes(data))]


def read_rows(reader, path: str) -> tuple[str, object]:
    """('ok', [row, ...]) or ('missing'|'denied'|'bad', message)."""
    base = os.path.basename(path)
    try:
        with open(path, "rb") as fh:
            plist = plistlib.load(fh)
    except FileNotFoundError:
        return "missing", f"{base} is missing"
    except OSError as exc:
        if exc.errno in (errno.EPERM, errno.EACCES):
            return "denied", f"{base} is unreadable (Full Disk Access)"
        return "bad", f"could not read {base} ({exc.strerror or exc})"
    except (plistlib.InvalidFileException, ValueError, TypeError) as exc:
        return "bad", f"could not read {base} ({exc})"
    if not isinstance(plist, dict) or "$objects" not in plist:
        return "bad", f"could not read {base} (not a sidebar archive)"
    objects = plist["$objects"]
    if not isinstance(objects, list):
        return "bad", f"could not read {base} (empty archive)"
    try:
        from plistlib import UID

        root_ref = UID(1)
        top = plist.get("$top")
        if isinstance(top, dict) and "root" in top:
            root_ref = top["root"]
        root = reader.deref(objects, root_ref)
        items_ref = reader.dict_get(objects, root, "items")
        if items_ref is None:
            return "bad", f"could not read {base} (no items)"
        item_refs = reader.as_uid_list(objects, items_ref)
        rows = []
        for index, item_ref in enumerate(item_refs):
            item = reader.deref(objects, item_ref)
            if not isinstance(item, dict):
                continue
            name = reader.dict_get(objects, item, "Name")
            if not isinstance(name, str):
                name = ""
            bookmark = reader.dict_get(objects, item, "Bookmark")
            path_value = reader.bookmark_path(bookmark) if bookmark is not None else None
            props = reader.dict_get(objects, item, "CustomItemProperties")
            hidden = None
            if isinstance(props, dict):
                hidden = as_hidden(reader.dict_get(objects, props, HIDDEN_KEY))
            rows.append(
                {
                    "name": name,
                    "path": path_value or "",
                    "hidden": hidden,
                    "strings": bookmark_strings(bookmark),
                    "index": index,
                    "label": name or "an unnamed row",
                }
            )
    except (TypeError, ValueError, IndexError, KeyError) as exc:
        return "bad", f"could not read {base} ({exc})"
    return "ok", rows


def recognizer(ident: str, home: str, user: str):
    home_path = home.rstrip("/")

    def is_shared(row: dict) -> bool:
        return row["name"] == "Shared"

    def is_airdrop(row: dict) -> bool:
        if row["name"] == "AirDrop":
            return True
        if row["path"]:
            return False
        return "AirDrop" in row["strings"]

    def is_icloud(row: dict) -> bool:
        if row["name"] == "iCloud Drive":
            return True
        return any("com~apple~CloudDocs" in item for item in row["strings"])

    def is_home(row: dict) -> bool:
        path = row["path"].rstrip("/")
        if home_path and path == home_path:
            return True
        return bool(user) and row["name"] == user

    def is_mac_hd(row: dict) -> bool:
        if row["name"] == "Macintosh HD":
            return True
        return row["path"] == "/" and row["name"] in ("", "Macintosh HD")

    def is_network(row: dict) -> bool:
        return row["name"] == "Network" or row["path"].rstrip("/") == "/Network"

    def is_trash(row: dict) -> bool:
        path = row["path"].rstrip("/")
        return row["name"] == "Trash" or path.endswith("/.Trash")

    found = {
        "shared": is_shared,
        "airdrop": is_airdrop,
        "icloud": is_icloud,
        "home": is_home,
        "macintosh-hd": is_mac_hd,
        "network": is_network,
        "trash": is_trash,
    }
    return found.get(ident)


def first_visible(rows: list[dict]) -> dict | None:
    for row in rows:
        if row["hidden"] is True:
            continue
        return row
    return None


def judge(rules, pools: dict[str, tuple[str, object]], home: str, user: str):
    """Yield (status, id, message). pools values are read_rows results."""
    titles_unread: dict[str, list[str]] = {"top": [], "volumes": []}
    unnamed: list[str] = []
    for ident, where, want in rules:
        title = TITLES.get(ident, ident)
        match = recognizer(ident, home, user)
        if match is None:
            emit_now = (
                "warn",
                ident,
                f"the sidebar row list names {ident}, which this check does"
                " not know how to find",
            )
            yield emit_now
            continue
        sources = ("top", "volumes") if where == "either" else (where,)
        readable: list[dict] = []
        saw_readable = False
        blocked: list[str] = []
        for source in sources:
            status, payload = pools[source]
            if status == "ok" and isinstance(payload, list):
                saw_readable = True
                readable.extend(payload)
            else:
                blocked.append(source)
        if not saw_readable:
            titles_unread[blocked[0]].append(title)
            continue
        matched = [row for row in readable if match(row)]
        if not matched:
            unnamed.append(title)
            continue
        if want == "hidden":
            shown = [row for row in matched if row["hidden"] is not True]
            if shown:
                yield (
                    "warn",
                    ident,
                    f"{title} is showing. Hide it in Finder → Settings → Sidebar."
                    + FIX,
                )
            else:
                yield "ok", ident, f"{title} is hidden"
            continue
        if want == "visible":
            hidden_rows = [row for row in matched if row["hidden"] is True]
            if hidden_rows:
                yield (
                    "warn",
                    ident,
                    f"{title} is hidden. Show it in Finder → Settings → Sidebar."
                    + FIX,
                )
            else:
                yield "ok", ident, f"{title} is showing"
            continue
        # first: visible, and the first visible row in the top section.
        top_status, top_rows = pools["top"]
        if top_status != "ok" or not isinstance(top_rows, list):
            titles_unread["top"].append(title)
            continue
        top_matched = [row for row in top_rows if match(row)]
        if not top_matched:
            unnamed.append(title)
            continue
        if any(row["hidden"] is True for row in top_matched):
            yield (
                "warn",
                ident,
                f"{title} is hidden. Show it at the top of the Finder sidebar."
                + FIX,
            )
            continue
        first = first_visible(top_rows)
        if first is not None and match(first):
            yield "ok", ident, f"{title} is the first visible row in the sidebar"
            continue
        lead = first["label"] if first is not None else "nothing"
        yield (
            "warn",
            ident,
            f"{title} is not the first visible row (the first one is {lead})."
            " Show it at the top of the Finder sidebar."
            + FIX,
        )
    for source, titles in titles_unread.items():
        if not titles:
            continue
        status, payload = pools[source]
        detail = payload if isinstance(payload, str) else "could not be read"
        kind = "top of the sidebar" if source == "top" else "Locations"
        joined = ", ".join(titles)
        yield (
            "info",
            source,
            f"The {kind} file {detail}, so these stay by hand: {joined}.",
        )
    if unnamed:
        yield (
            "info",
            "unnamed",
            "These sidebar rows were not named in the sidebar files, so they"
            " stay by hand: " + ", ".join(unnamed) + ".",
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="finder-sidebar-rows.py", description=__doc__)
    parser.add_argument("--list", default=DEFAULT_LIST)
    parser.add_argument("--top", default="", help="TopSidebarSection sfl to read")
    parser.add_argument("--volumes", default="", help="FavoriteVolumes sfl to read")
    parser.add_argument("--home", default="", help="home folder path; default $HOME")
    parser.add_argument("--user", default="", help="short user name; default the home folder name")
    args = parser.parse_args(argv)
    home = args.home or os.environ.get("HOME", "")
    user = args.user or (os.path.basename(home.rstrip("/")) if home else "")
    try:
        rules = load_rules(args.list)
        reader = load_reader()
    except Exception as exc:  # noqa: BLE001 - report, don't crash the check
        emit("warn", "-", f"could not load the sidebar row check ({exc})")
        return 0
    directory = os.path.join(home, SIDEBAR_DIR) if home else ""
    top = args.top or (existing_file(directory, TOP_NAMES) if directory else "")
    volumes = args.volumes or (existing_file(directory, VOLUME_NAMES) if directory else "")
    if not top or not volumes:
        emit("info", "-", "the home folder is unknown, so the sidebar rows stay by hand")
        return 0
    pools = {
        "top": read_rows(reader, top),
        "volumes": read_rows(reader, volumes),
    }
    for status, ident, message in judge(rules, pools, home, user):
        emit(status, ident, message)
    return 0


if __name__ == "__main__":
    sys.exit(main())
