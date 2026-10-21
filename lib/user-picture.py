#!/usr/bin/env python3
"""Check that the account picture is the Dog.

The picture is the JPEGPhoto attribute on the user account. The bytes are
the hex dump with the first line dropped, which is the same pipeline as:

    dscl . -read /Users/$USER JPEGPhoto | tail -n +2 | xxd -r -p

The SHA-256 of those bytes is lib/user-picture.sha256. A different picture
is a warning. Nothing here writes the account or runs dscl. The shell check
runs dscl and passes the text in.

Output is one line: ok||message or warn||message.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_EXPECT = os.path.join(HERE, "user-picture.sha256")


def emit(status: str, message: str) -> None:
    text = str(message).replace("\n", " ").replace("|", "/")
    print(f"{status}||{text}")


def load_expect(path: str) -> str:
    found = ""
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.split("#", 1)[0].strip().lower()
            if not line:
                continue
            if not re.fullmatch(r"[0-9a-f]{64}", line):
                name = os.path.basename(path)
                raise ValueError(f"{name} should contain one SHA-256 hex line")
            if found:
                name = os.path.basename(path)
                raise ValueError(f"{name} has more than one SHA-256")
            found = line
    if not found:
        raise ValueError(f"{os.path.basename(path)} has no SHA-256")
    return found


def photo_bytes(text: str) -> bytes | None:
    """Bytes from a dscl JPEGPhoto dump. The first line is the label."""
    lines = text.splitlines()
    if len(lines) <= 1:
        return None
    digits = re.sub(r"[^0-9A-Fa-f]", "", "".join(lines[1:]))
    if len(digits) < 2:
        return None
    if len(digits) % 2:
        digits = digits[:-1]
    return bytes.fromhex(digits)


def judge(text: str, expect: str) -> tuple[str, str]:
    raw = photo_bytes(text)
    where = (
        " System Settings → Users & Groups → your account picture."
        " macconfig does not change this"
    )
    if raw is None:
        return (
            "warn",
            "the account picture could not be read, so it was not checked"
            " against the Dog." + where,
        )
    digest = hashlib.sha256(raw).hexdigest()
    if digest == expect:
        return "ok", "account picture is the Dog"
    return (
        "warn",
        f"account picture is not the Dog (this picture is SHA-256 {digest},"
        f" the Dog is {expect})." + where,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="user-picture.py", description=__doc__)
    parser.add_argument("--expect", default=DEFAULT_EXPECT, help="SHA-256 file")
    parser.add_argument(
        "--dump",
        default="",
        help="dscl JPEGPhoto text to read instead of stdin",
    )
    args = parser.parse_args(argv)
    try:
        expect = load_expect(args.expect)
    except OSError as exc:
        emit("warn", f"could not read the Dog picture hash ({exc})")
        return 0
    except ValueError as exc:
        emit("warn", str(exc))
        return 0
    if args.dump:
        try:
            with open(args.dump, encoding="utf-8") as fh:
                text = fh.read()
        except OSError as exc:
            emit("warn", f"could not read the account picture dump ({exc})")
            return 0
    else:
        text = sys.stdin.read()
    status, message = judge(text, expect)
    emit(status, message)
    return 0


if __name__ == "__main__":
    sys.exit(main())
