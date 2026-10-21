#!/usr/bin/env python3
"""Compare Finder sidebar Favorites with lib/sidebar-favorites.list.

`mysides list` prints one favorite per line: `Name -> file:///path/`.
Only file addresses are compared. Other lines (AirDrop and similar) are
not Favorites this repo sets, so they are left out of the comparison and
are not removed.

Commands (stdout):
  compare --list FILE --mysides FILE
      ok|message
      bad|message
      warn|message
  paths --list FILE
      name<TAB>expanded path, in list order
  urls --list FILE
      name<TAB>file:// address, in list order
  names --mysides FILE
      one file-favorite name per line (the ones a rebuild removes)
"""
from __future__ import annotations

import argparse
import os
import sys
from urllib.parse import quote, unquote, urlparse


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


def parse_mysides(text: str) -> list[tuple[str, str]]:
    """File favorites only, as (name, normalized path), in list order."""
    found: list[tuple[str, str]] = []
    for raw in text.splitlines():
        line = raw.strip()
        if " -> " not in line:
            continue
        name, url = line.rsplit(" -> ", 1)
        name = name.strip()
        url = url.strip()
        if not url.startswith("file:"):
            continue
        found.append((name, norm_path(url)))
    return found


def compare(desired: list[tuple[str, str]], actual: list[tuple[str, str]]) -> tuple[str, str]:
    if not desired:
        return "warn", "sidebar favorites list is empty — Favorites were not changed"
    want = [(name, norm_path(path)) for name, path in desired]
    if actual == want:
        names = ", ".join(name for name, _path in want)
        return "ok", f"Finder Favorites match ({names})"
    have = ", ".join(
        f"{name or '(no name)'} ({tilde(path)})" for name, path in actual
    ) or "(none)"
    need = ", ".join(f"{name} ({tilde(path)})" for name, path in want)
    return "bad", f"Favorites are {have}; want {need}"


def emit_status(status: str, message: str) -> None:
    text = message.replace("\n", " ").replace("|", "/")
    print(f"{status}|{text}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="sidebar-favorites.py", description=__doc__)
    parser.add_argument("command", choices=("compare", "paths", "urls", "names"))
    parser.add_argument("--list", default="", help="lib/sidebar-favorites.list")
    parser.add_argument("--mysides", default="", help="saved `mysides list` output")
    args = parser.parse_args(argv)
    try:
        if args.command in ("compare", "paths", "urls"):
            if not args.list:
                emit_status("warn", "sidebar favorites list path is missing")
                return 0
            desired = load_desired(args.list)
        else:
            desired = []
        if args.command == "paths":
            for name, path in desired:
                print(f"{name}\t{norm_path(path)}")
            return 0
        if args.command == "urls":
            for name, path in desired:
                print(f"{name}\t{file_url(path)}")
            return 0
        if not args.mysides:
            emit_status("warn", "mysides list output is missing")
            return 0
        with open(args.mysides, encoding="utf-8") as fh:
            text = fh.read()
        if args.command == "names":
            for name, _path in parse_mysides(text):
                if name:
                    print(name)
            return 0
        status, message = compare(desired, parse_mysides(text))
        emit_status(status, message)
        return 0
    except Exception as exc:  # noqa: BLE001 - report, don't crash macos.sh
        emit_status("warn", f"could not compare Finder Favorites ({exc})")
        return 0


if __name__ == "__main__":
    sys.exit(main())
