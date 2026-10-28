#!/usr/bin/env python3
"""Check display modes, and plan a displayplacer command.

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

The same list pins the ARZOPA portable monitor (`external|...` rows). It is
connected when some non-built-in display's `_name` is the row's name, or
when a serial field on that display matches the row's serial. The persistent
screen id is not used: macOS replaces it when the cable moves to another
port. The check then reads `displayplacer list` (passed with `--placer`) and
compares resolution, refresh, scaling, and origin. The row's refresh rate is
the preferred one. When that screen lists no mode at the pinned resolution and
scaling at that rate (a dock that tops out at 144Hz), the highest rate it does
list there is expected instead. A matching displayplacer
screen is chosen by serial, then by name, then by type — and type counts
only when that block does not name a different product or serial. When the
monitor is absent the line is info, not a warning. Without `--placer` a
connected monitor is `pending`, so the caller can read `displayplacer list`
and run again.

One line, fields separated by `|`:

    ok||message
    warn||message
    info||message
    error||message
    pending|arzopa|message
    ok|arzopa|message
    warn|arzopa|message
    info|arzopa|message

`--plan --placer FILE` reads `displayplacer list` output. When the built-in
panel is not already More Space, it prints that status line and then one
`screen|<displayplacer arg>` line per screen. The built-in screen switches to
the More Space mode (scaling on, current refresh rate when that mode exists).
Every other screen is repeated with its current mode so it is not changed,
except a connected ARZOPA that is not already on its pin: that screen is set
to the pinned mode and origin `(-width,0)`, and the laptop display's origin
is set to `(0,0)` so it stays the main display. A pinned monitor that is set
also prints `rate|arzopa|<hz>`, the refresh rate in its screen line.
`--max-hz N` leaves out the pinned monitor's rates above N, so a caller whose
displayplacer set did not take can ask for the next rate down. This file does
not run displayplacer. A missing mode is a warning and no screen lines. Exit
status is 0 whenever a line was printed.
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


def load_config(path: str) -> tuple[dict[str, str], list[dict]]:
    """Panel prefixes, then external pins, from lib/display-resolution.list."""
    rows: dict[str, str] = {}
    pins: list[dict] = []
    seen_names: set[str] = set()
    with open(path, encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            body = raw.split("#", 1)[0].strip()
            if not body:
                continue
            if body.startswith("external|"):
                pins.append(_parse_pin(path, lineno, body))
                key = pins[-1]["name"].lower()
                if key in seen_names:
                    raise ValueError(
                        f"{os.path.basename(path)}:{lineno}: {pins[-1]['name']} listed twice"
                    )
                seen_names.add(key)
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
    return rows, pins


def _parse_pin(path: str, lineno: int, body: str) -> dict:
    parts = [part.strip() for part in body.split("|")]
    name = os.path.basename(path)
    if len(parts) != 8:
        raise ValueError(
            f"{name}:{lineno}: want external|<name>|<serial>|<type>|"
            "<width>x<height>|<hz>|off|left"
        )
    _, label, serial, kind, res, hz, scaling, place = parts
    if not label or not serial or not kind:
        raise ValueError(f"{name}:{lineno}: name, serial, and type are required")
    if not re.fullmatch(r"s?\d+", serial, re.I):
        raise ValueError(f"{name}:{lineno}: serial should look like s74646035")
    if not re.fullmatch(r"\d+x\d+", res):
        raise ValueError(f"{name}:{lineno}: resolution should look like 1920x1080")
    if not re.fullmatch(r"\d+", hz):
        raise ValueError(f"{name}:{lineno}: refresh rate should be a number")
    if scaling.lower() not in ("on", "off"):
        raise ValueError(f"{name}:{lineno}: scaling should be on or off")
    if place != "left":
        raise ValueError(f"{name}:{lineno}: place should be left")
    return {
        "name": label,
        "serial": serial,
        "type": kind,
        "res": res,
        "hz": hz,
        "scaling": scaling.lower(),
        "place": place,
    }


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


# displayplacer prints `scaling:on` on a scaled mode and nothing on an unscaled
# one, and marks the mode in use with `<-- current mode`:
#   mode 61: res:1920x1080 hz:144 color_depth:8 <-- current mode
#   mode 97: res:1920x1080 hz:144 color_depth:8 scaling:on
MODE_RE = re.compile(
    r"^[ \t]*mode[ \t]+(\d+):[ \t]+res:(\d+)x(\d+)[ \t]+hz:(\d+)[ \t]+color_depth:(\d+)"
    r"(?:[ \t]+scaling:(on|off))?([ \t]*<--[ \t]*current mode)?",
    re.I | re.M,
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
                "scaling": (match.group(6) or "off").lower(),
                "res": f"{match.group(2)}x{match.group(3)}",
                "current": bool(match.group(7)),
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
                "name": (
                    _field(block, "Screen name")
                    or _field(block, "Display name")
                    or _field(block, "Name")
                ),
                "serial": _field(block, "Serial screen id"),
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
    """The mode marked `<-- current mode`, else the first one that matches the header."""
    marked = [mode for mode in screen["modes"] if mode.get("current")]
    if len(marked) == 1:
        return marked[0]
    matches = [
        mode
        for mode in screen["modes"]
        if mode["res"] == screen["res"]
        and (not screen["hz"] or mode["hz"] == screen["hz"])
        and (not screen["depth"] or mode["depth"] == screen["depth"])
        and (not screen["scaling"] or mode["scaling"] == screen["scaling"])
    ]
    return matches[0] if matches else None


def _mode_arg(screen: dict, mode: dict, origin: str | None = None) -> str:
    origin = origin or screen.get("origin") or ""
    if not origin:
        return ""
    degree = screen.get("degree") or "0"
    return f"id:{screen['id']} mode:{mode['n']} origin:{origin} degree:{degree}"


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


def emit_pin(status: str, message: str) -> None:
    text = str(message).replace("\n", " ").replace("|", "/")
    print(f"{status}|arzopa|{text}")


def _norm_serial(value: str) -> str:
    text = re.sub(r"\s+", "", value.strip().lower())
    if text.startswith("s") and text[1:].isdigit():
        return text[1:]
    return text


def _norm_type(value: str) -> str:
    return " ".join(value.lower().replace("-", " ").split())


def _drv_serial(drv: dict) -> str:
    for key, val in drv.items():
        if "serial" in str(key).lower() and isinstance(val, str) and val.strip():
            return _norm_serial(val)
    return ""


def _want_origin(pin: dict) -> str:
    width = pin["res"].split("x", 1)[0]
    return f"(-{int(width)},0)"


def _profiler_connected(displays: list[dict], pin: dict) -> bool:
    """True when system_profiler shows this monitor.

    Name and serial come from the panel itself. The displayplacer persistent
    id is not in this report and is not consulted.
    """
    want_name = pin["name"].lower()
    want_serial = _norm_serial(pin["serial"])
    for drv in displays:
        if is_builtin(drv):
            continue
        if panel_name(drv).lower() == want_name:
            return True
        serial = _drv_serial(drv)
        if want_serial and serial and serial == want_serial:
            return True
    return False


def _placer_candidates(screens: list[dict], pin: dict) -> list[dict]:
    """displayplacer screens for this pin.

    Serial wins, then an exact name, then the type. Type is displayplacer's
    size class ("16 inch external screen"), so it is used only when the block
    does not already name a different product or carry a different serial.
    A persistent screen id is never enough on its own.
    """
    want_name = pin["name"].lower()
    want_serial = _norm_serial(pin["serial"])
    want_type = _norm_type(pin["type"])
    serial_hits: list[dict] = []
    name_hits: list[dict] = []
    type_hits: list[dict] = []
    for screen in screens:
        if not screen.get("id") or _builtin_screen(screen):
            continue
        name = str(screen.get("name") or "").strip().lower()
        serial = _norm_serial(str(screen.get("serial") or ""))
        kind = _norm_type(str(screen.get("type") or ""))
        if want_serial and serial and serial == want_serial:
            serial_hits.append(screen)
            continue
        if name and name == want_name:
            name_hits.append(screen)
            continue
        if want_type and kind == want_type:
            if name and name != want_name:
                continue
            if serial and want_serial and serial != want_serial:
                continue
            type_hits.append(screen)
    if serial_hits:
        return serial_hits
    if name_hits:
        return name_hits
    return type_hits


def _pick_exact(modes: list[dict], res: str, hz: str, scaling: str) -> dict | None:
    width, height = (int(part) for part in res.split("x", 1))
    pool = [
        mode
        for mode in modes
        if mode["w"] == width
        and mode["h"] == height
        and mode["hz"] == hz
        and mode["scaling"] == scaling
    ]
    if not pool:
        return None
    preferred = [mode for mode in pool if mode["depth"] == "8"]
    pool = preferred or pool
    return sorted(pool, key=lambda mode: int(mode["n"]))[0]


def _pin_arg(screen: dict, mode: dict, origin: str) -> str:
    return (
        f"id:{screen['id']} res:{mode['res']} hz:{mode['hz']} "
        f"color_depth:{mode['depth']} enabled:true scaling:{mode['scaling']} "
        f"origin:{origin} degree:0"
    )


def _read_screens(placer_text: str) -> tuple[list[dict] | None, str | None]:
    if not placer_text.strip():
        return None, "empty"
    declared = len(re.findall(r"^Persistent screen id:", placer_text, re.M))
    screens = parse_placer(placer_text)
    if declared == 0 or declared != len(screens) or any(not screen.get("id") for screen in screens):
        return None, "unreadable"
    return screens, None


def _offered_rates(modes: list[dict], res: str, scaling: str) -> list[int]:
    """Refresh rates listed at this resolution and scaling, highest first."""
    width, height = (int(part) for part in res.split("x", 1))
    rates = {
        int(mode["hz"])
        for mode in modes
        if mode["w"] == width and mode["h"] == height and mode["scaling"] == scaling
    }
    return sorted(rates, reverse=True)


def _target_rate(pin: dict, offered: list[int], max_hz: int | None) -> tuple[str, str]:
    """(rate to expect, why it is not the pinned rate). ("", "") when none is left.

    The pinned rate wins when it is listed. Otherwise the highest listed rate
    does. --max-hz drops the rates a caller could not set.
    """
    usable = [rate for rate in offered if max_hz is None or rate <= max_hz]
    if not usable:
        return "", ""
    preferred = int(pin["hz"])
    if preferred in usable:
        return pin["hz"], ""
    if usable[0] == offered[0]:
        return str(usable[0]), (
            f"the highest this connection offers ({pin['hz']}Hz needs a direct connection)"
        )
    return str(usable[0]), "the highest rate displayplacer could set"


def _arrangement(screen: dict, screens: list[dict], pin: dict, why: str = "") -> tuple[bool, str]:
    want = _want_origin(pin)
    rate = f"{pin['hz']}Hz, {why}," if why else f"{pin['hz']}Hz,"
    problems: list[str] = []
    if screen.get("res") != pin["res"]:
        problems.append(f"resolution {screen.get('res') or 'unknown'}")
    if screen.get("hz") != pin["hz"]:
        problems.append(f"{screen.get('hz') or 'unknown'}Hz")
    if screen.get("scaling") != pin["scaling"]:
        problems.append(f"scaling {screen.get('scaling') or 'unknown'}")
    if screen.get("depth") and screen.get("depth") != "8":
        problems.append(f"color depth {screen.get('depth')}")
    if (screen.get("degree") or "0") != "0":
        problems.append(f"rotation {screen.get('degree')}")
    if screen.get("origin") != want:
        problems.append(f"origin {screen.get('origin') or 'unknown'}")
    laptops = [other for other in screens if _builtin_screen(other)]
    if len(laptops) != 1:
        problems.append("laptop display was not found")
    elif laptops[0].get("origin") != "(0,0)":
        problems.append(f"laptop display origin {laptops[0].get('origin') or 'unknown'}")
    if not problems:
        return True, (
            f"{pin['name']} is {pin['res']} at {rate} scaling {pin['scaling']}, "
            f"at {want}, to the left of the laptop. The laptop stays at (0,0), "
            "so the Dock and menu bar stay on it"
        )
    return False, (
        f"{pin['name']} is not in its place ({'; '.join(problems)}; "
        f"want {pin['res']} at {rate} scaling {pin['scaling']}, "
        f"origin {want}, laptop at (0,0)). "
        "macos.sh sets this with displayplacer when that mode is listed; "
        "otherwise System Settings → Displays"
    )


def evaluate_pin(
    displays: list[dict], pin: dict, placer_text: str | None, max_hz: int | None = None
) -> dict:
    """One external pin: info if absent, pending if its list was not read."""
    origin = _want_origin(pin)
    base = {
        "name": pin["name"],
        "res": pin["res"],
        "hz": pin["hz"],
        "scaling": pin["scaling"],
        "origin": origin,
        "fix": False,
        "mode": None,
        "screen": None,
    }
    if not _profiler_connected(displays, pin):
        return {
            **base,
            "status": "info",
            "message": f"{pin['name']} not connected — resolution and position not checked",
        }
    if placer_text is None:
        return {
            **base,
            "status": "pending",
            "message": (
                f"{pin['name']} is connected but displayplacer list was not read, so "
                f"{pin['res']} at {pin['hz']}Hz (or the highest rate the connection "
                f"offers), scaling {pin['scaling']}, "
                f"to the left of the laptop (origin {origin}) was not checked. "
                "Run brewsync to install displayplacer, or set it by hand "
                "(System Settings → Displays)"
            ),
        }
    screens, kind = _read_screens(placer_text)
    if kind is not None or screens is None:
        return {
            **base,
            "status": "warn",
            "message": (
                f"{pin['name']}: displayplacer list could not be read, so the monitor "
                "was not checked. Set it by hand (System Settings → Displays)"
            ),
        }
    hits = _placer_candidates(screens, pin)
    if len(hits) != 1:
        if not hits:
            message = (
                f"{pin['name']} is connected but displayplacer list has no screen "
                f"named {pin['name']}, with serial {pin['serial']}, or of type "
                f"{pin['type']} without a different name or serial. "
                "The persistent screen id is not used. "
                "Set it by hand (System Settings → Displays)"
            )
        else:
            message = (
                f"{pin['name']}: displayplacer list has {len(hits)} matching screens "
                "(name, serial, or type). The persistent screen id is not used, "
                "so nothing was changed"
            )
        return {**base, "status": "warn", "message": message}
    screen = hits[0]
    offered = _offered_rates(screen["modes"], pin["res"], pin["scaling"])
    hz, why = _target_rate(pin, offered, max_hz)
    if not hz:
        if offered:
            listed = ", ".join(str(rate) for rate in offered)
            problem = (
                f"displayplacer could not set {pin['res']} with scaling {pin['scaling']} "
                f"at any listed refresh rate ({listed}Hz)"
            )
        else:
            problem = (
                f"displayplacer has no mode {pin['res']} with scaling {pin['scaling']} "
                "at any refresh rate"
            )
        return {
            **base,
            "status": "warn",
            "message": (
                f"{pin['name']}: {problem} — set it by hand "
                "(System Settings → Displays). Other displays were not changed"
            ),
        }
    want = {**pin, "hz": hz}
    base["hz"] = hz
    mode = _pick_exact(screen["modes"], pin["res"], hz, pin["scaling"])
    ok, message = _arrangement(screen, screens, want, why)
    if ok:
        return {**base, "status": "ok", "message": message, "screen": screen, "mode": mode}
    laptops = [other for other in screens if _builtin_screen(other)]
    return {
        **base,
        "status": "warn",
        "message": message,
        "screen": screen,
        "mode": mode,
        "fix": len(laptops) == 1,
    }


def _plan_builtin_only(builtins: list[dict], prefixes: dict[str, str], placer_text: str) -> None:
    """More Space for the built-in panel. Other screens keep their current mode."""
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


def _plan_with_pins(
    builtins: list[dict],
    prefixes: dict[str, str],
    actionable: list[dict],
    placer_text: str,
) -> None:
    """Set each pinned monitor, and More Space too when the laptop needs it."""
    builtin_needed = _needs_apply(builtins, prefixes)
    names = ", ".join(ev["name"] for ev in actionable)
    screens, kind = _read_screens(placer_text)
    if kind == "empty":
        if builtin_needed:
            _manual(
                "displayplacer list returned nothing — set More Space by hand"
                " (System Settings → Displays)."
            )
        emit_pin(
            "warn",
            f"{names}: displayplacer list returned nothing — set the monitor by hand"
            " (System Settings → Displays)",
        )
        return
    if kind == "unreadable" or screens is None:
        if builtin_needed:
            _manual(
                "could not read every screen from displayplacer list — set More Space"
                " by hand (System Settings → Displays)."
            )
        emit_pin(
            "warn",
            f"{names}: could not read every screen from displayplacer list — set the"
            " monitor by hand (System Settings → Displays)",
        )
        return
    builtin_screens = [screen for screen in screens if _builtin_screen(screen)]
    if len(builtin_screens) != 1:
        if builtin_needed:
            _manual(
                "could not match the built-in display in displayplacer list — set More"
                " Space by hand (System Settings → Displays)."
            )
        emit_pin(
            "warn",
            f"{names}: the laptop display is not in displayplacer list, so the monitor"
            " was not moved",
        )
        return
    builtin = builtin_screens[0]
    builtin_mode: dict | None
    builtin_size: tuple[int, int] | None = None
    if builtin_needed:
        jobs = _mismatch_prefixes(builtins, prefixes)
        if len(jobs) != 1:
            _manual(
                "could not match the built-in display in displayplacer list — set More"
                " Space by hand (System Settings → Displays)."
            )
            emit_pin("warn", f"{names} was not changed")
            return
        builtin_size = _parse_wh(jobs[0])
        if builtin_size is None:
            _manual("the More Space size in lib/display-resolution.list is not width x height.")
            return
        builtin_mode = _pick_mode(
            builtin["modes"], builtin_size[0], builtin_size[1], builtin["hz"], builtin["depth"]
        )
        if builtin_mode is None:
            _manual(
                f"displayplacer has no More Space mode {builtin_size[0]}x{builtin_size[1]}"
                " (scaling on) for the built-in display — set it by hand"
                " (System Settings → Displays)."
            )
            for ev in actionable:
                emit_pin("warn", ev["message"])
            return
    else:
        builtin_mode = _current_mode(builtin)
        if builtin_mode is None:
            emit_pin(
                "warn",
                f"{names}: could not read the laptop display's current mode, so the"
                " monitor was not changed",
            )
            return
    by_id = {ev["screen"]["id"]: ev for ev in actionable}
    args: list[str] = []
    for screen in screens:
        if screen["id"] in by_id:
            ev = by_id[screen["id"]]
            arg = _pin_arg(screen, ev["mode"], ev["origin"])
        elif screen["id"] == builtin["id"]:
            arg = _mode_arg(screen, builtin_mode, origin="(0,0)")
        else:
            current = _current_mode(screen)
            arg = _mode_arg(screen, current) if current is not None else _property_arg(screen)
        if not arg:
            if builtin_needed:
                _manual(
                    "could not read a display's current mode — set More Space by hand"
                    " (System Settings → Displays)."
                )
            emit_pin(
                "warn",
                f"{names}: could not read a display's current mode, so the monitor"
                " was not changed",
            )
            return
        args.append(arg)
    if builtin_needed and builtin_size is not None and builtin_mode is not None:
        emit(
            "apply",
            f"built-in display More Space {builtin_size[0]}x{builtin_size[1]}"
            f" at {builtin_mode['hz']}Hz, scaling on",
        )
    for ev in actionable:
        emit(
            "apply",
            f"{ev['name']} {ev['res']} at {ev['hz']}Hz, scaling {ev['scaling']},"
            " left of the laptop",
        )
        print(f"rate|arzopa|{ev['hz']}")
    for arg in args:
        print(f"screen|{arg}")


def plan_apply(
    displays: list[dict],
    builtins: list[dict],
    prefixes: dict[str, str],
    pins: list[dict],
    placer_text: str,
    max_hz: int | None = None,
) -> None:
    """Print a displayplacer plan, or the check lines when nothing should change."""
    evals = [evaluate_pin(displays, pin, placer_text, max_hz) for pin in pins]
    actionable = [ev for ev in evals if ev.get("fix")]
    if actionable:
        _plan_with_pins(builtins, prefixes, actionable, placer_text)
        return
    if not _needs_apply(builtins, prefixes):
        describe(builtins, prefixes)
        for ev in evals:
            emit_pin(ev["status"], ev["message"])
        return
    _plan_builtin_only(builtins, prefixes, placer_text)
    for ev in evals:
        if ev["status"] == "warn":
            emit_pin(ev["status"], ev["message"])


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
        help="plan a displayplacer command when a managed display is not in place",
    )
    parser.add_argument(
        "--placer",
        default="",
        help="file of displayplacer list output (checks the ARZOPA pin, and --plan)",
    )
    parser.add_argument(
        "--max-hz",
        type=int,
        default=None,
        help="leave out the pinned monitor's refresh rates above this",
    )
    args = parser.parse_args(argv)
    try:
        prefixes, pins = load_config(args.list)
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
    placer: str | None = None
    if args.placer:
        try:
            with open(args.placer, encoding="utf-8") as fh:
                placer = fh.read()
        except Exception as exc:  # noqa: BLE001 - a missing list is a report
            emit("warn", f"could not read displayplacer list ({exc})")
            return 0
    if args.plan:
        plan_apply(
            displays, builtins, prefixes, pins, "" if placer is None else placer, args.max_hz
        )
    else:
        describe(builtins, prefixes)
        for pin in pins:
            ev = evaluate_pin(displays, pin, placer, args.max_hz)
            emit_pin(ev["status"], ev["message"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
