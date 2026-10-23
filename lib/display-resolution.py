#!/usr/bin/env python3
"""Read-only check that the built-in display is on More Space.

`system_profiler SPDisplaysDataType -json` lists each GPU's `spdisplays_ndrvs`.
A built-in panel is a drive whose `spdisplays_connection_type` is
`spdisplays_internal`. When that key is absent, `_name` `Color LCD` is the
built-in panel. No such drive (lid closed, external display only) is an info
skip, not a warning.

The panel size comes from `spdisplays_pixelresolution` (for example
`spdisplays_3024x1964Retina`). lib/display-resolution.list maps each panel
size to the start of its More Space `_spdisplays_resolution`: 3024x1964 (14")
is `1800 x 1169` and 3456x2234 (16") is `2056 x 1329`. The live string looks
like `1800 x 1169 @ 120.00Hz`. A panel size not in the list is an info line.

One line, fields separated by `|`:

    ok||message
    warn||message
    info||message
    error||message

Nothing here writes a display mode. `--fix` does not change it either.
Exit status is 0 whenever a line was printed.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_LIST = os.path.join(HERE, "display-resolution.list")
INTERNAL = "spdisplays_internal"


def emit(status: str, message: str) -> None:
    text = str(message).replace("\n", " ").replace("|", "/")
    print(f"{status}||{text}")


PANEL_RE = re.compile(r"(\d{3,5})\s*x\s*(\d{3,5})")


def load_prefixes(path: str) -> dict[str, str]:
    rows: dict[str, str] = {}
    with open(path, encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            body = raw.split("#", 1)[0].strip()
            if not body:
                continue
            panel, sep, prefix = body.partition("|")
            panel = panel.strip()
            if not sep or not re.fullmatch(r"\d+x\d+", panel) or not prefix.strip():
                raise ValueError(
                    f"{os.path.basename(path)}:{lineno}: want <width>x<height>|<prefix>"
                )
            if panel in rows:
                raise ValueError(f"{os.path.basename(path)}:{lineno}: {panel} listed twice")
            rows[panel] = prefix.strip()
    if not rows:
        raise ValueError(f"{os.path.basename(path)}: no panel rows")
    return rows


def panel_size(drv: dict) -> str:
    raw = drv.get("spdisplays_pixelresolution")
    if not isinstance(raw, str):
        return ""
    match = PANEL_RE.search(raw)
    return f"{match.group(1)}x{match.group(2)}" if match else ""


def is_builtin(drv: dict) -> bool:
    conn = drv.get("spdisplays_connection_type")
    if isinstance(conn, str) and conn:
        return conn == INTERNAL
    return drv.get("_name") == "Color LCD"


def panel_name(drv: dict) -> str:
    name = drv.get("_name")
    if isinstance(name, str) and name.strip():
        return name.strip()
    return "built-in display"


def iter_displays(data: object) -> list[dict]:
    if not isinstance(data, dict):
        raise ValueError("profiler JSON root is not an object")
    blocks = data.get("SPDisplaysDataType")
    if not isinstance(blocks, list):
        raise ValueError("profiler JSON has no SPDisplaysDataType array")
    found: list[dict] = []
    for block in blocks:
        if not isinstance(block, dict):
            continue
        drives = block.get("spdisplays_ndrvs")
        if not isinstance(drives, list):
            continue
        for drv in drives:
            if isinstance(drv, dict):
                found.append(drv)
    return found


def describe(builtins: list[dict], prefixes: dict[str, str]) -> None:
    if not builtins:
        emit(
            "info",
            "no built-in display — More Space not checked"
            " (clamshell or external display only)",
        )
        return
    mismatches: list[str] = []
    shown: list[str] = []
    unknown: list[str] = []
    wanted: list[str] = []
    for drv in builtins:
        name = panel_name(drv)
        panel = panel_size(drv)
        prefix = prefixes.get(panel)
        if prefix is None:
            unknown.append(f"{name} {panel or 'size not reported'}")
            continue
        wanted.append(prefix)
        resolution = drv.get("_spdisplays_resolution")
        if not isinstance(resolution, str) or not resolution:
            mismatches.append(f"{name}: _spdisplays_resolution is missing")
            continue
        if resolution.startswith(prefix):
            shown.append(f"{name} '{resolution}'")
        else:
            mismatches.append(f"{name}: _spdisplays_resolution is '{resolution}'")
    want = ", ".join(dict.fromkeys(wanted))
    if mismatches:
        detail = "; ".join(mismatches)
        emit(
            "warn",
            f"Built-in display is not More Space ({detail}; want"
            f" _spdisplays_resolution to start with {want}) — System Settings"
            " → Displays. macconfig-check.sh --fix does not change this",
        )
        return
    if unknown and not shown:
        known = ", ".join(sorted(prefixes))
        emit(
            "info",
            f"built-in panel size not in lib/display-resolution.list"
            f" ({'; '.join(unknown)}; known: {known}) — More Space not checked",
        )
        return
    joined = "; ".join(shown)
    emit(
        "ok",
        f"Built-in display is More Space ({joined}; _spdisplays_resolution"
        f" starts with {prefix})",
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="display-resolution.py", description=__doc__)
    parser.add_argument(
        "--json",
        help="system_profiler SPDisplaysDataType -json file (default: stdin)",
    )
    parser.add_argument("--list", default=DEFAULT_LIST, help="expected prefix list")
    args = parser.parse_args(argv)
    try:
        prefixes = load_prefixes(args.list)
    except FileNotFoundError as exc:
        emit("error", f"display resolution list missing ({exc.filename})")
        return 0
    except Exception as exc:  # noqa: BLE001 - report, don't crash macconfig-check.sh
        emit("error", f"could not read the display resolution list ({exc})")
        return 0
    try:
        if args.json:
            with open(args.json, encoding="utf-8") as fh:
                raw = fh.read()
        else:
            raw = sys.stdin.read()
        data = json.loads(raw)
        displays = iter_displays(data)
    except Exception as exc:  # noqa: BLE001 - a torn profiler dump is a report
        emit("error", f"could not read system_profiler JSON ({exc})")
        return 0
    describe([drv for drv in displays if is_builtin(drv)], prefixes)
    return 0


if __name__ == "__main__":
    sys.exit(main())
