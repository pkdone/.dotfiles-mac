#!/usr/bin/env python3
"""Read-only check that idle sleep is off on mains power.

`pmset -g custom` prints one block per power profile. Only the `AC Power:`
block is read, and only its `sleep` key (minutes until idle system sleep, or
0 to disable it). `displaysleep`, `Sleep On Power Button`, and the
`Battery Power:` block are ignored, so the display can still turn off, the
screen can still lock, and battery settings stay as they are.

One line, fields separated by `|`:

    ok||message
    bad||message     sleep is present and is not 0
    warn||message    the AC block or the sleep key could not be read

`sleep 0` does not stop the Mac sleeping when the lid is closed. Nothing
here writes. Setting the value is `sudo pmset -c sleep 0` (manual step
`ac-sleep`); `--fix` does not run sudo.
"""
from __future__ import annotations

import argparse
import sys

AC_HEADER = "AC Power:"


def emit(status: str, message: str) -> None:
    text = str(message).replace("\n", " ").replace("|", "/")
    print(f"{status}||{text}")


def is_header(line: str) -> bool:
    stripped = line.strip()
    return bool(stripped) and stripped.endswith(":") and not line[:1].isspace()


def ac_section(text: str) -> str | None:
    """Body of the first AC Power block, or None when that header is absent."""
    found = False
    body: list[str] = []
    for raw in text.splitlines():
        line = raw.replace("\r", "").rstrip()
        if is_header(line):
            if found:
                break
            if line.strip() == AC_HEADER:
                found = True
            continue
        if found:
            body.append(line)
    if not found:
        return None
    return "\n".join(body)


def sleep_token(section: str) -> str | None:
    """The AC `sleep` value. `displaysleep` and `Sleep On Power Button` do not match."""
    for raw in section.splitlines():
        parts = raw.split()
        if len(parts) >= 2 and parts[0] == "sleep":
            return parts[1]
    return None


def judge(text: str) -> tuple[str, str]:
    section = ac_section(text)
    if section is None:
        return (
            "warn",
            "pmset -g custom has no 'AC Power:' section"
            " — can't tell if idle sleep is off on mains power",
        )
    token = sleep_token(section)
    if token is None:
        return (
            "warn",
            "AC Power section has no sleep value"
            " — can't tell if idle sleep is off on mains power",
        )
    if not _is_int(token):
        return (
            "warn",
            f"AC Power sleep value '{token}' is not a number"
            " — can't tell if idle sleep is off on mains power",
        )
    if token == "0":
        return (
            "ok",
            "AC idle sleep is off (sleep 0). The display still turns off and"
            " the screen still locks. Closing the lid still sleeps the Mac,"
            " and battery is unchanged",
        )
    return (
        "bad",
        f"AC idle sleep is {token} (want 0) — mains-power sleep is no longer 0,"
        " so the Mac can sleep on its own while plugged in. This often happens"
        " after an MDM (Kandji) reset. Run sudo pmset -c sleep 0 (manual step"
        " ac-sleep). macconfig-check.sh --fix does not change this (it needs"
        " sudo). The display still turns off and the screen still locks."
        " Closing the lid still sleeps the Mac, and battery is unchanged",
    )


def _is_int(token: str) -> bool:
    if token.startswith("-"):
        token = token[1:]
    return bool(token) and token.isdigit()


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
    except Exception as exc:  # noqa: BLE001 - report, don't crash macconfig-check.sh
        emit("warn", f"could not read pmset -g custom ({exc})")
        return 0
    status, message = judge(data)
    emit(status, message)
    return 0


if __name__ == "__main__":
    sys.exit(main())
