#!/usr/bin/env python3
"""Check that the built-in display is on More Space, and plan a displayplacer command.

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

`--plan --placer FILE` reads `displayplacer list` output. When the built-in
panel is not already More Space, it prints that status line and then one
`screen|<displayplacer arg>` line per screen. The built-in screen switches to
the More Space mode (scaling on, current refresh rate when that mode exists).
Every other screen is repeated with its current mode so it is not changed.
This file does not run displayplacer. A missing mode is a warning and no
screen lines. Exit status is 0 whenever a line was printed.
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
            f" _spdisplays_resolution to start with {want})."
            " macos.sh sets this with displayplacer when that mode is listed;"
            " otherwise System Settings → Displays",
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


MODE_RE = re.compile(
    r"mode\s+(\d+):\s+res:(\d+)x(\d+)\s+hz:(\d+)\s+color_depth:(\d+)\s+scaling:(on|off)",
    re.I,
)


def _field(block: str, label: str) -> str:
    match = re.search(rf"^{re.escape(label)}:[ \t]*(.+)$", block, re.M)
    return match.group(1).strip() if match else ""


def _compact_res(raw: str) -> str:
    match = re.search(r"(\d+)\s*x\s*(\d+)", raw)
    return f"{match.group(1)}x{match.group(2)}" if match else ""


def _first_int(raw: str) -> str:
    match = re.search(r"\d+", raw)
    return match.group(0) if match else ""


def _scaling(raw: str) -> str:
    text = raw.strip().lower()
    if text.startswith("on"):
        return "on"
    if text.startswith("off"):
        return "off"
    return ""


def _origin(raw: str) -> str:
    match = re.search(r"\(\s*-?\d+\s*,\s*-?\d+\s*\)", raw)
    if not match:
        return ""
    return re.sub(r"\s+", "", match.group(0))


def _modes(block: str) -> list[dict]:
    found: list[dict] = []
    for match in MODE_RE.finditer(block):
        found.append(
            {
                "n": match.group(1),
                "w": int(match.group(2)),
                "h": int(match.group(3)),
                "hz": match.group(4),
                "depth": match.group(5),
                "scaling": match.group(6).lower(),
                "res": f"{match.group(2)}x{match.group(3)}",
            }
        )
    return found


def parse_placer(text: str) -> list[dict]:
    """Screens from `displayplacer list`. The suggested command at the end is ignored."""
    screens: list[dict] = []
    chunks = re.split(r"(?=^Persistent screen id:)", text, flags=re.M)
    for chunk in chunks:
        if "Persistent screen id:" not in chunk:
            continue
        lines: list[str] = []
        for line in chunk.splitlines():
            stripped = line.strip()
            if stripped.startswith("Execute the command") or stripped.startswith("displayplacer "):
                break
            lines.append(line)
        block = "\n".join(lines)
        sid = _field(block, "Persistent screen id")
        if not sid or not re.fullmatch(r"[A-Za-z0-9_.:-]+", sid):
            screens.append({})
            continue
        screens.append(
            {
                "id": sid,
                "type": _field(block, "Type"),
                "res": _compact_res(_field(block, "Resolution")),
                "hz": _first_int(_field(block, "Hertz")),
                "depth": _first_int(_field(block, "Color Depth")),
                "scaling": _scaling(_field(block, "Scaling")),
                "origin": _origin(_field(block, "Origin")),
                "degree": _first_int(_field(block, "Rotation")) or "0",
                "modes": _modes(block),
            }
        )
    return screens


def _builtin_screen(screen: dict) -> bool:
    kind = str(screen.get("type", "")).lower().replace("-", " ")
    return "built in" in kind or "internal" in kind


def _parse_wh(prefix: str) -> tuple[int, int] | None:
    match = re.fullmatch(r"(\d+)\s*x\s*(\d+)", prefix.strip())
    if not match:
        return None
    return int(match.group(1)), int(match.group(2))


def _needs_apply(builtins: list[dict], prefixes: dict[str, str]) -> bool:
    if not builtins:
        return False
    for drv in builtins:
        prefix = prefixes.get(panel_size(drv))
        if prefix is None:
            continue
        resolution = drv.get("_spdisplays_resolution")
        if not isinstance(resolution, str) or not resolution.startswith(prefix):
            return True
    return False


def _mismatch_prefixes(builtins: list[dict], prefixes: dict[str, str]) -> list[str]:
    jobs: list[str] = []
    for drv in builtins:
        prefix = prefixes.get(panel_size(drv))
        if prefix is None:
            continue
        resolution = drv.get("_spdisplays_resolution")
        if isinstance(resolution, str) and resolution.startswith(prefix):
            continue
        jobs.append(prefix)
    return jobs


def _pick_mode(modes: list[dict], width: int, height: int, hz: str, depth: str) -> dict | None:
    """More Space is a scaled mode. Prefer the current refresh rate, then colour depth."""
    pool = [m for m in modes if m["w"] == width and m["h"] == height and m["scaling"] == "on"]
    if not pool:
        return None

    def rank(mode: dict) -> tuple[int, int, int]:
        try:
            dist = abs(int(mode["hz"]) - int(hz))
        except ValueError:
            dist = 999
        depth_penalty = 0 if depth and mode["depth"] == depth else (0 if not depth else 1)
        return (dist, depth_penalty, int(mode["n"]))

    return sorted(pool, key=rank)[0]


def _current_mode(screen: dict) -> dict | None:
    matches = [
        mode
        for mode in screen["modes"]
        if mode["res"] == screen["res"]
        and (not screen["hz"] or mode["hz"] == screen["hz"])
        and (not screen["depth"] or mode["depth"] == screen["depth"])
        and (not screen["scaling"] or mode["scaling"] == screen["scaling"])
    ]
    return matches[0] if matches else None


def _mode_arg(screen: dict, mode: dict) -> str:
    if not screen.get("origin"):
        return ""
    degree = screen.get("degree") or "0"
    return f"id:{screen['id']} mode:{mode['n']} origin:{screen['origin']} degree:{degree}"


def _property_arg(screen: dict) -> str:
    if not screen.get("id") or not screen.get("res") or not screen.get("origin"):
        return ""
    parts = [f"id:{screen['id']}", f"res:{screen['res']}"]
    if screen.get("hz"):
        parts.append(f"hz:{screen['hz']}")
    if screen.get("depth"):
        parts.append(f"color_depth:{screen['depth']}")
    if screen.get("scaling"):
        parts.append(f"scaling:{screen['scaling']}")
    parts.append(f"origin:{screen['origin']}")
    parts.append(f"degree:{screen.get('degree') or '0'}")
    return " ".join(parts)


def _manual(message: str) -> None:
    text = message.rstrip()
    if text.endswith("."):
        text = text[:-1]
    emit("warn", f"built-in display: {text}. Other displays were not changed")


def plan_apply(builtins: list[dict], prefixes: dict[str, str], placer_text: str) -> None:
    """Print a displayplacer plan, or the same check line when nothing should change."""
    if not _needs_apply(builtins, prefixes):
        describe(builtins, prefixes)
        return
    if not placer_text.strip():
        _manual(
            "displayplacer list returned nothing — set More Space by hand"
            " (System Settings → Displays)."
        )
        return
    declared = len(re.findall(r"^Persistent screen id:", placer_text, re.M))
    screens = parse_placer(placer_text)
    if declared == 0 or declared != len(screens) or any(not screen.get("id") for screen in screens):
        _manual(
            "could not read every screen from displayplacer list — set More Space"
            " by hand (System Settings → Displays)."
        )
        return
    builtin_screens = [screen for screen in screens if _builtin_screen(screen)]
    jobs = _mismatch_prefixes(builtins, prefixes)
    if len(builtin_screens) != 1 or len(jobs) != 1:
        _manual(
            "could not match the built-in display in displayplacer list — set More"
            " Space by hand (System Settings → Displays)."
        )
        return
    size = _parse_wh(jobs[0])
    if size is None:
        _manual("the More Space size in lib/display-resolution.list is not width x height.")
        return
    screen = builtin_screens[0]
    mode = _pick_mode(screen["modes"], size[0], size[1], screen["hz"], screen["depth"])
    if mode is None:
        _manual(
            f"displayplacer has no More Space mode {size[0]}x{size[1]} (scaling on)"
            " for the built-in display — set it by hand (System Settings → Displays)."
        )
        return
    args: list[str] = []
    for other in screens:
        if other is screen:
            arg = _mode_arg(other, mode)
        else:
            current = _current_mode(other)
            arg = _mode_arg(other, current) if current is not None else _property_arg(other)
        if not arg:
            _manual(
                "could not read a display's current mode — set More Space by hand"
                " (System Settings → Displays)."
            )
            return
        args.append(arg)
    emit(
        "apply",
        f"built-in display More Space {size[0]}x{size[1]} at {mode['hz']}Hz, scaling on",
    )
    for arg in args:
        print(f"screen|{arg}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="display-resolution.py", description=__doc__)
    parser.add_argument(
        "--json",
        help="system_profiler SPDisplaysDataType -json file (default: stdin)",
    )
    parser.add_argument("--list", default=DEFAULT_LIST, help="expected prefix list")
    parser.add_argument(
        "--plan",
        action="store_true",
        help="plan a displayplacer command when the built-in display is not More Space",
    )
    parser.add_argument(
        "--placer",
        default="",
        help="file of displayplacer list output (used with --plan)",
    )
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
    builtins = [drv for drv in displays if is_builtin(drv)]
    if args.plan:
        placer = ""
        if args.placer:
            try:
                with open(args.placer, encoding="utf-8") as fh:
                    placer = fh.read()
            except Exception as exc:  # noqa: BLE001 - a missing list is a report
                emit("warn", f"could not read displayplacer list ({exc})")
                return 0
        plan_apply(builtins, prefixes, placer)
    else:
        describe(builtins, prefixes)
    return 0


if __name__ == "__main__":
    sys.exit(main())
