#!/usr/bin/env python3
"""Compare and apply Finder double-click default apps against lib/file-handlers.list.

Check (the default) is read-only. One line per extension, fields separated by `|`:

    ok|ext|message
    bad|ext|message
    info|ext|message
    warn||message

`duti -x <ext>` prints the default app's display name, path, and bundle id
(the bundle id is the last non-empty line). No handler is duti's
"Failed to get default application" on stderr, exit 2: that extension is unset.

`--apply` sets each drifted row with `duti -s <bundle-id> .<ext> all`, plus any
extra UTIs named on the row (`uti:…`). It then polls `duti -x` for a few
seconds, because Launch Services often applies the change after duti returns.
`--dry-run` changes nothing. `--only` is a comma-separated list of extensions.

Rows marked `unpinnable` (no declared UTI; duti error -50 on the dynamic UTI)
are reported as info and never passed to duti.

html / htm / xhtml, the UTIs public.html and public.xhtml, and any URL scheme
are refused. Setting public.html switches the default web browser. URL schemes
are `duti -s <bundle> <scheme>` with no role (`all` is error -50) and belong
in lib/url-handlers.list.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import time

EXT_RE = re.compile(r"[A-Za-z0-9]+$")
BUNDLE_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9.-]*$")
UTI_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9.-]+$")
NO_HANDLER = "Failed to get default application"
BROWSER_EXTS = {"html", "htm", "xhtml"}
BROWSER_UTIS = {"public.html", "public.xhtml"}
# Always blocked, even when lib/url-handlers.list is not beside the file list.
BUILTIN_SCHEMES = {
    "http", "https", "mailto", "ftp", "ftps", "file",
}


def emit(status: str, ext: str, message: str) -> None:
    text = str(message).replace("\n", " ").replace("|", "/")
    print(f"{status}|{ext}|{text}")


def settle_seconds() -> float:
    raw = os.environ.get("FILE_HANDLERS_SETTLE_SECS", "5")
    try:
        return max(0.0, float(raw))
    except ValueError:
        return 5.0


def load_schemes(list_path: str) -> set[str]:
    schemes = set(BUILTIN_SCHEMES)
    sibling = os.path.join(os.path.dirname(os.path.abspath(list_path)), "url-handlers.list")
    if not os.path.isfile(sibling):
        return schemes
    with open(sibling, encoding="utf-8") as fh:
        for line in fh:
            raw = line.strip()
            if not raw or raw.startswith("#"):
                continue
            schemes.add(raw.split("|", 1)[0].strip().lower())
    return schemes


def load_rows(path: str) -> list[tuple[str, str, str, str, tuple[str, ...]]]:
    """Rows are (ext, app, bundle, mode, extra_utis). mode is '' or 'unpinnable'."""
    rows = []
    with open(path, encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            raw = line.strip()
            if not raw or raw.startswith("#"):
                continue
            parts = [p.strip() for p in raw.split("|")]
            if len(parts) not in (3, 4) or not parts[0] or not parts[1] or not parts[2]:
                raise ValueError(f"line {lineno}: want extension|app|bundle-id[|unpinnable|uti:…]")
            ext, app, bundle = parts[0], parts[1], parts[2]
            flag = parts[3] if len(parts) == 4 else ""
            if ext.startswith("."):
                ext = ext[1:]
            ext = ext.lower()
            if not EXT_RE.fullmatch(ext):
                raise ValueError(f"line {lineno}: extension {ext!r} is not a bare word")
            if not BUNDLE_RE.fullmatch(bundle):
                raise ValueError(f"line {lineno}: bundle id {bundle!r} is not usable")
            mode = ""
            extra: tuple[str, ...] = ()
            if flag == "":
                pass
            elif flag == "unpinnable":
                mode = "unpinnable"
            elif flag.startswith("uti:"):
                extra = tuple(u.strip() for u in flag[4:].split(",") if u.strip())
                if not extra:
                    raise ValueError(f"line {lineno}: uti: needs at least one UTI")
            else:
                raise ValueError(f"line {lineno}: flag {flag!r} is not unpinnable or uti:…")
            rows.append((ext, app, bundle, mode, extra))
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


def extension_utis(duti: str, ext: str) -> list[str]:
    """UTIs `duti -e` declares for this extension. Empty if duti can't say."""
    rc, out, _err = run_duti([duti, "-e", ext])
    if rc != 0 and "identifier:" not in out:
        return []
    found = []
    for line in out.splitlines():
        stripped = line.strip()
        if stripped.lower().startswith("identifier:"):
            found.append(stripped.split(":", 1)[1].strip())
    return found


def browser_refusal(ext: str, extra: tuple[str, ...], schemes: set[str], declared: list[str]) -> str:
    """Why this row must not be applied, or '' if it is safe to set."""
    if ext in BROWSER_EXTS:
        return (
            f"refusing .{ext}: tied to the default web browser"
            " (public.html / public.xhtml). Leave it with the browser;"
            " http and https are lib/url-handlers.list"
        )
    if ext in schemes or ":" in ext:
        return (
            f"refusing {ext}: URL schemes are not file handlers."
            " Use `duti -s <bundle> <scheme>` with no role (role all is error -50),"
            " from lib/url-handlers.list"
        )
    blocked = []
    for uti in list(extra) + list(declared):
        low = uti.lower()
        if low in BROWSER_UTIS or low in schemes or low in BROWSER_EXTS:
            blocked.append(uti)
        elif not UTI_RE.fullmatch(uti):
            blocked.append(uti)
    if blocked:
        return (
            f"refusing .{ext}: {' '.join(blocked)} is tied to the default browser"
            " or is not a UTI. File handlers never set public.html, public.xhtml,"
            " or a URL scheme"
        )
    return ""


def label(app: str, bundle: str) -> str:
    return f"{app} / {bundle}"


def unpinnable_message(ext: str, shown: str) -> str:
    return (
        f".{ext} can't be pinned (no declared UTI; duti error -50 on the dynamic UTI;"
        f" currently {shown}). Not DRIFT"
    )


def check_rows(duti: str, rows, schemes: set[str]) -> list[tuple[str, str, str]]:
    out = []
    seen: set[str] = set()
    for ext, app, bundle, mode, extra in rows:
        if ext in seen:
            out.append(("warn", ext, f"duplicate extension .{ext}"))
            continue
        seen.add(ext)
        reason = browser_refusal(ext, extra, schemes, [])
        if reason:
            out.append(("warn", ext, reason))
            continue
        if mode == "unpinnable":
            have, err = current_handler(duti, ext)
            shown = err or have or "unset"
            out.append(("info", ext, unpinnable_message(ext, shown)))
            continue
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


def wait_for_handler(duti: str, ext: str, bundle: str) -> tuple[str, str]:
    """Poll duti -x until it shows bundle, or the settle window ends."""
    deadline = time.monotonic() + settle_seconds()
    last_have, last_err = "", ""
    while True:
        last_have, last_err = current_handler(duti, ext)
        if not last_err and last_have == bundle:
            return last_have, ""
        if time.monotonic() >= deadline:
            return last_have, last_err
        time.sleep(0.25)


def apply_rows(duti: str, rows, tokens: list[str], schemes: set[str], dry_run: bool):
    selected = set(tokens)
    out = []
    seen: set[str] = set()
    known: set[str] = set()
    for ext, app, bundle, mode, extra in rows:
        known.add(ext)
        if selected and ext not in selected:
            continue
        if ext in seen:
            out.append(("refuse", ext, f"duplicate extension .{ext}"))
            continue
        seen.add(ext)
        if mode == "unpinnable":
            have, _err = current_handler(duti, ext)
            out.append(("info", ext, unpinnable_message(ext, have or "unset")))
            continue
        declared = [] if dry_run else extension_utis(duti, ext)
        reason = browser_refusal(ext, extra, schemes, declared)
        if reason:
            out.append(("refuse", ext, reason))
            continue
        have, err = current_handler(duti, ext)
        if err:
            out.append(("fail", ext, f".{ext}: {err}"))
            continue
        if have == bundle:
            out.append(("ok", ext, f".{ext} already {label(app, bundle)}"))
            continue
        shown = have or "unset"
        if dry_run:
            extra_note = f" plus {', '.join(extra)}" if extra else ""
            out.append(("dry", ext, f".{ext}: {shown} -> {label(app, bundle)}{extra_note}"))
            continue
        failed = ""
        for uti in extra:
            rc, _so, se = run_duti([duti, "-s", bundle, uti, "all"])
            if rc != 0:
                detail = se.strip().replace("\n", " ") or f"exit {rc}"
                failed = f"duti -s {bundle} {uti} all failed: {detail}"
                break
        if not failed:
            rc, _so, se = run_duti([duti, "-s", bundle, f".{ext}", "all"])
            if rc != 0:
                detail = se.strip().replace("\n", " ") or f"exit {rc}"
                failed = f"duti -s {bundle} .{ext} all failed: {detail}"
        if failed:
            out.append(("fail", ext, failed))
            continue
        have_after, err_after = wait_for_handler(duti, ext, bundle)
        if err_after or have_after != bundle:
            still = have_after or "unset"
            detail = err_after or f"duti -x still shows {still}"
            out.append((
                "fail", ext,
                f"duti -s {bundle} .{ext} all did not stick after {settle_seconds():g}s: {detail}"))
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
    schemes = load_schemes(args.list_path)
    duti = duti_bin()
    if not duti:
        message = "duti not installed — file handlers not checked"
        if not args.apply:
            emit("warn", "", message)
            return 0
        tokens = [t.strip().lstrip(".").lower() for t in args.only.split(",") if t.strip()]
        targets = tokens or [ext for ext, _app, _bundle, _mode, _extra in rows]
        for ext in targets:
            emit("fail", ext, "duti not installed — file handler not changed")
        return 1
    if not args.apply:
        for status, ext, message in check_rows(duti, rows, schemes):
            emit(status, ext, message)
        return 0
    tokens = [t.strip().lstrip(".").lower() for t in args.only.split(",") if t.strip()]
    plans = apply_rows(duti, rows, tokens, schemes, args.dry_run)
    for status, ext, message in plans:
        emit(status, ext, message)
    if any(status in ("fail", "refuse") for status, _ext, _message in plans):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
