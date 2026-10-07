#!/usr/bin/env python3
"""Compare and apply Finder double-click default apps against lib/file-handlers.list.

Check (the default) is read-only. One line per extension, fields separated by `|`:

    ok|ext|message
    bad|ext|message
    warn||message

`duti -x <ext>` prints the default app's display name, path, and bundle id
(the bundle id is the last non-empty line). No handler is duti's
"Failed to get default application" on stderr, exit 2: that extension is unset.

`--apply` sets each drifted row with `duti -s <bundle-id> .<ext> all` and
leaves rows that already match alone. It reads `duti -x` again afterwards
and reports `fail` if the handler did not change. `--dry-run` changes
nothing. `--only` is a comma-separated list of extensions.

Extensions with no declared UTI (.env, .list) are passed through the same
way. duti resolves them to a dynamic UTI conforming to public.content and
sets the handler on that; a duti refusal is a `fail` line, not a skip.
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys

EXT_RE = re.compile(r"\.?[A-Za-z0-9]+$")
BUNDLE_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9.-]*$")
NO_HANDLER = "Failed to get default application"


def emit(status: str, ext: str, message: str) -> None:
    text = str(message).replace("\n", " ").replace("|", "/")
    print(f"{status}|{ext}|{text}")


def load_rows(path: str) -> list[tuple[str, str, str]]:
    rows = []
    with open(path, encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            raw = line.strip()
            if not raw or raw.startswith("#"):
                continue
            parts = [p.strip() for p in raw.split("|")]
            if len(parts) != 3 or not all(parts):
                raise ValueError(f"line {lineno}: want extension|app|bundle-id")
            ext, app, bundle = parts
            if ext.startswith("."):
                ext = ext[1:]
            ext = ext.lower()
            if not EXT_RE.fullmatch(ext):
                raise ValueError(f"line {lineno}: extension {ext!r} is not a bare word")
            if not BUNDLE_RE.fullmatch(bundle):
                raise ValueError(f"line {lineno}: bundle id {bundle!r} is not usable")
            rows.append((ext, app, bundle))
    return rows


def duti_bin() -> str:
    return shutil.which("duti") or ""


def run_duti(argv: list[str]) -> tuple[int, str, str]:
    proc = subprocess.run(argv, capture_output=True, check=False, text=True)
    return proc.returncode, proc.stdout or "", proc.stderr or ""


def bundle_from_duti_x(stdout: str) -> str:
    """duti -x prints name, app path, then bundle id. The bundle id is last."""
    lines = [ln.strip() for ln in stdout.splitlines() if ln.strip()]
    if not lines:
        return ""
    return lines[-1]


def current_handler(duti: str, ext: str) -> tuple[str, str]:
    """Return (bundle, error). An extension with no handler is ("", "")."""
    rc, out, err = run_duti([duti, "-x", ext])
    bundle = bundle_from_duti_x(out)
    if rc == 0 and bundle:
        return bundle, ""
    err_s = err.strip().replace("\n", " ")
    if NO_HANDLER in err_s or (rc != 0 and not bundle and not err_s):
        return "", ""
    if rc != 0 and not bundle:
        return "", err_s or f"duti -x {ext} exited {rc}"
    if bundle:
        return bundle, ""
    return "", ""


def label(app: str, bundle: str) -> str:
    return f"{app} / {bundle}"


def check_rows(duti: str, rows: list[tuple[str, str, str]]) -> list[tuple[str, str, str]]:
    out = []
    seen: set[str] = set()
    for ext, app, bundle in rows:
        if ext in seen:
            out.append(("warn", ext, f"duplicate extension .{ext}"))
            continue
        seen.add(ext)
        have, err = current_handler(duti, ext)
        if err:
            out.append(("warn", ext, f".{ext}: {err}"))
            continue
        if have == bundle:
            out.append(("ok", ext, f".{ext} -> {label(app, bundle)}"))
        else:
            shown = have or "unset"
            out.append(("bad", ext, f".{ext} -> {shown} (expected {label(app, bundle)})"))
    return out


def apply_rows(duti: str, rows, tokens: list[str], dry_run: bool) -> list[tuple[str, str, str]]:
    selected = set(tokens)
    out = []
    seen: set[str] = set()
    known: set[str] = set()
    for ext, app, bundle in rows:
        known.add(ext)
        if selected and ext not in selected:
            continue
        if ext in seen:
            out.append(("refuse", ext, f"duplicate extension .{ext}"))
            continue
        seen.add(ext)
        have, err = current_handler(duti, ext)
        if err:
            out.append(("fail", ext, f".{ext}: {err}"))
            continue
        if have == bundle:
            out.append(("ok", ext, f".{ext} already {label(app, bundle)}"))
            continue
        shown = have or "unset"
        if dry_run:
            out.append(("dry", ext, f".{ext}: {shown} -> {label(app, bundle)}"))
            continue
        rc, _so, se = run_duti([duti, "-s", bundle, f".{ext}", "all"])
        if rc != 0:
            detail = se.strip().replace("\n", " ") or f"exit {rc}"
            out.append((
                "fail", ext,
                f"duti -s {bundle} .{ext} all failed: {detail}"))
            continue
        have_after, err_after = current_handler(duti, ext)
        if err_after or have_after != bundle:
            still = have_after or "unset"
            detail = err_after or f"duti -x still shows {still}"
            out.append((
                "fail", ext,
                f"duti -s {bundle} .{ext} all did not stick: {detail}"))
            continue
        out.append(("chg", ext, f".{ext}: {shown} -> {label(app, bundle)}"))
    for token in tokens:
        if token not in known:
            out.append(("refuse", token, "not in lib/file-handlers.list"))
    return out


def report_bad_list(apply: bool, exc: Exception) -> int:
    message = f"could not read the file-handler list ({exc})"
    emit("fail" if apply else "warn", "", message)
    return 1 if apply else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="file-handlers.py", description=__doc__)
    parser.add_argument("list_path", help="pipe-delimited extension|app|bundle-id list")
    parser.add_argument("--apply", action="store_true", help="set drifted handlers with duti -s")
    parser.add_argument("--dry-run", action="store_true", help="with --apply, change nothing")
    parser.add_argument("--only", default="", help="comma-separated extensions to apply")
    args = parser.parse_args(argv)
    if args.dry_run:
        args.apply = True
    try:
        rows = load_rows(args.list_path)
    except Exception as exc:  # noqa: BLE001 - report, don't crash check.sh
        return report_bad_list(args.apply, exc)
    duti = duti_bin()
    if not duti:
        message = "duti not installed — file handlers not checked"
        if not args.apply:
            emit("warn", "", message)
            return 0
        tokens = [t.strip().lstrip(".").lower() for t in args.only.split(",") if t.strip()]
        targets = tokens or [ext for ext, _app, _bundle in rows]
        for ext in targets:
            emit("fail", ext, "duti not installed — file handler not changed")
        return 1
    if not args.apply:
        for status, ext, message in check_rows(duti, rows):
            emit(status, ext, message)
        return 0
    tokens = [t.strip().lstrip(".").lower() for t in args.only.split(",") if t.strip()]
    plans = apply_rows(duti, rows, tokens, args.dry_run)
    for status, ext, message in plans:
        emit(status, ext, message)
    if any(status in ("fail", "refuse") for status, _ext, _message in plans):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
