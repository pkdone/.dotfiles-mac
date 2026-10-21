#!/usr/bin/env python3
"""Read-only check of sleep, display sleep, and wake for network access.

`pmset -g custom` prints one block per power profile. This reads:

  - AC Power `sleep` — want 0 (the Mac does not sleep on its own while plugged in)
  - AC Power `displaysleep` — want 10 (the display sleeps after 10 minutes)
  - Battery Power `displaysleep` — want 2 (the display sleeps after 2 minutes)
  - AC Power `womp` — want 1 (wake for network access while plugged in)

Battery idle sleep, the lock screen, and Sleep On Power Button are not read.
Closing the lid still sleeps the Mac.

One line, fields separated by `|`:

    ok||message
    bad|pmset args;pmset args|message
    warn||message

`bad` lists only the `pmset` commands that still need to run, without `sudo`.
A missing block or key is `warn` (the command is not guessed). Nothing here
writes. `macos.sh` may run the sudo commands and skips them when sudo is not
available. `macconfig --fix` does not run sudo.
"""
from __future__ import annotations

import argparse
import sys

# profile header, key, wanted value, pmset command without sudo, plain name
CHECKS = (
    (
        "AC Power:",
        "sleep",
        "0",
        "pmset -c sleep 0",
        "on mains power the Mac does not sleep on its own (sleep 0)",
    ),
    (
        "AC Power:",
        "displaysleep",
        "10",
        "pmset -c displaysleep 10",
        "on mains power the display sleeps after 10 minutes",
    ),
    (
        "Battery Power:",
        "displaysleep",
        "2",
        "pmset -b displaysleep 2",
        "on battery the display sleeps after 2 minutes",
    ),
    (
        "AC Power:",
        "womp",
        "1",
        "pmset -c womp 1",
        "on mains power, wake for network access is on",
    ),
)

OK_TAIL = (
    " Closing the lid still sleeps the Mac. Battery idle sleep is not changed."
    " macconfig --fix does not change this (it needs sudo)"
)


def emit(status: str, commands: list[str], message: str) -> None:
    cmds = ";".join(commands).replace("|", "/")
    text = str(message).replace("\n", " ").replace("|", "/")
    print(f"{status}|{cmds}|{text}")


def is_header(line: str) -> bool:
    stripped = line.strip()
    return bool(stripped) and stripped.endswith(":") and not line[:1].isspace()


def section_body(text: str, header: str) -> str | None:
    found = False
    body: list[str] = []
    for raw in text.splitlines():
        line = raw.replace("\r", "").rstrip()
        if is_header(line):
            if found:
                break
            if line.strip() == header:
                found = True
            continue
        if found:
            body.append(line)
    if not found:
        return None
    return "\n".join(body)


def key_token(section: str, key: str) -> str | None:
    """The value of `key`. A longer name such as displaysleep does not match sleep."""
    for raw in section.splitlines():
        parts = raw.split()
        if len(parts) >= 2 and parts[0] == key:
            return parts[1]
    return None


def _is_int(token: str) -> bool:
    number = token[1:] if token.startswith("-") else token
    return bool(number) and number.isdigit()


def judge(text: str) -> tuple[str, list[str], str]:
    problems: list[str] = []
    commands: list[str] = []
    saw_bad = False
    saw_warn = False
    sections: dict[str, str | None] = {}
    for header, _key, _want, _cmd, _plain in CHECKS:
        if header not in sections:
            sections[header] = section_body(text, header)
    for header, key, want, command, plain in CHECKS:
        body = sections[header]
        if body is None:
            saw_warn = True
            problems.append(
                f"pmset -g custom has no '{header}' section, so this could not"
                f" be checked: {plain}"
            )
            continue
        token = key_token(body, key)
        if token is None:
            saw_warn = True
            problems.append(
                f"{header[:-1]} has no {key} value, so this could not be"
                f" checked: {plain}"
            )
            continue
        if not _is_int(token):
            saw_warn = True
            problems.append(
                f"{header[:-1]} {key} value '{token}' is not a number,"
                f" so this could not be checked: {plain}"
            )
            continue
        if token != want:
            saw_bad = True
            commands.append(command)
            problems.append(f"{plain}, but it is {token} (want {want})")
    if saw_bad:
        shown = "; ".join(f"sudo {cmd}" for cmd in commands)
        body = ". ".join(problems)
        if not body.endswith("."):
            body += "."
        message = (
            body
            + f" Run {shown}. macconfig --fix does not run sudo."
            + " Closing the lid still sleeps the Mac."
            + " Battery idle sleep is not changed."
        )
        return "bad", commands, message
    if saw_warn:
        body = ". ".join(problems)
        if body and not body.endswith("."):
            body += "."
        return "warn", [], body
    goods = [plain[0].upper() + plain[1:] + "." for _h, _k, _w, _c, plain in CHECKS]
    return "ok", [], " ".join(goods) + OK_TAIL


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ac-sleep.py", description=__doc__)
    parser.add_argument("--text", default="", help="read this pmset -g custom dump instead of stdin")
    args = parser.parse_args(argv)
    try:
        if args.text:
            with open(args.text, encoding="utf-8") as fh:
                data = fh.read()
        else:
            data = sys.stdin.read()
    except Exception as exc:  # noqa: BLE001 - report, don't crash the check
        emit("warn", [], f"could not read pmset -g custom ({exc})")
        return 0
    status, commands, message = judge(data)
    emit(status, commands, message)
    return 0


if __name__ == "__main__":
    sys.exit(main())
