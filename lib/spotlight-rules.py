#!/usr/bin/env python3
"""Compare Spotlight app results with lib/spotlight-apps.list.

Reads EnabledPreferenceRules from a `defaults export` of com.apple.Spotlight,
or from JSON passed to --json (tests). The 13 apps in the list should be off.

How the value is read:
  - An array of names or bundle ids is the set that is on. Each listed app
    must be absent.
  - A dictionary is the same when every value is on. If any value is off,
    each listed app must be present and off.
  - An array of dictionaries is read the same way, using an enabled flag and
    a name or bundle id on each one.
  - Anything else is a warning, not a pass.

Nothing here writes.
"""
from __future__ import annotations

import argparse
import json
import plistlib
import sys
from typing import Any


def load_apps(path: str) -> list[tuple[str, str]]:
    apps: list[tuple[str, str]] = []
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.split("#", 1)[0].strip()
            if not line or "|" not in line:
                continue
            name, bundle = line.split("|", 1)
            name = name.strip()
            bundle = bundle.strip()
            if name and bundle:
                apps.append((name, bundle))
    return apps


def emit(status: str, message: str) -> None:
    text = message.replace("\n", " ").replace("|", "/")
    print(f"{status}|{text}")


def is_off(value: Any) -> bool:
    if isinstance(value, bool):
        return value is False
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value == 0
    if isinstance(value, str):
        return value.strip().lower() in {"0", "false", "no", "off"}
    return False


def is_on(value: Any) -> bool:
    if isinstance(value, bool):
        return value is True
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value == 1
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return False


def ident_matches(text: str, name: str, bundle: str) -> bool:
    token = text.strip().lower()
    return token == name.lower() or token == bundle.lower()


def _strings(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        found: list[str] = []
        for item in value.values():
            found.extend(_strings(item))
        return found
    if isinstance(value, list):
        found = []
        for item in value:
            found.extend(_strings(item))
        return found
    return []


def dict_enabled(entry: dict[str, Any]) -> Any:
    for key in ("enabled", "Enabled", "isEnabled"):
        if key in entry:
            return entry[key]
    return None


def dict_idents(entry: dict[str, Any]) -> list[str]:
    found: list[str] = []
    for key in (
        "bundleID",
        "bundleId",
        "BundleIdentifier",
        "id",
        "name",
        "Name",
        "application",
    ):
        value = entry.get(key)
        if isinstance(value, str):
            found.append(value)
    if not found:
        found.extend(_strings(entry))
    return found


def entry_matches(entry: dict[str, Any], name: str, bundle: str) -> bool:
    return any(ident_matches(token, name, bundle) for token in dict_idents(entry))


def judge(rules: Any, apps: list[tuple[str, str]]) -> tuple[str, str]:
    if not apps:
        return "warn", "Spotlight app list is empty — results were not checked"
    if isinstance(rules, list) and all(isinstance(item, str) for item in rules):
        on = [
            name
            for name, bundle in apps
            if any(ident_matches(item, name, bundle) for item in rules)
        ]
        if on:
            joined = ", ".join(on)
            return "warn", f"{joined} Spotlight results are on (want off)"
        return "ok", f"Spotlight results are off for {len(apps)} apps"
    if isinstance(rules, dict):
        return _judge_mapped(rules.items(), apps, "dictionary")
    if isinstance(rules, list) and all(isinstance(item, dict) for item in rules):
        pairs = []
        for entry in rules:
            flag = dict_enabled(entry)
            for token in dict_idents(entry):
                pairs.append((token, flag))
        return _judge_mapped(pairs, apps, "list")
    kind = type(rules).__name__
    return (
        "warn",
        f"EnabledPreferenceRules is a {kind}, which this check does not"
        " understand yet — check System Settings → Spotlight → Results from Apps",
    )


def _judge_mapped(pairs: Any, apps: list[tuple[str, str]], shape: str) -> tuple[str, str]:
    items = list(pairs)
    flags = [value for _key, value in items]
    stores_off = any(is_off(value) for value in flags)
    on: list[str] = []
    missing: list[str] = []
    unclear: list[str] = []
    for name, bundle in apps:
        found = [value for key, value in items if ident_matches(str(key), name, bundle)]
        if not found:
            if stores_off:
                missing.append(name)
            continue
        if any(is_on(value) for value in found):
            on.append(name)
        elif any(value is None or not is_off(value) for value in found):
            unclear.append(name)
    if on or missing or unclear:
        parts: list[str] = []
        if on:
            parts.append(f"{', '.join(on)} Spotlight results are on (want off)")
        if missing:
            parts.append(f"{', '.join(missing)} is not listed as off")
        if unclear:
            parts.append(f"{', '.join(unclear)} could not be read as off")
        return "warn", "; ".join(parts)
    return "ok", f"Spotlight results are off for {len(apps)} apps ({shape})"


def rules_from_plist(path: str) -> Any:
    with open(path, "rb") as fh:
        data = plistlib.load(fh)
    if isinstance(data, dict) and "EnabledPreferenceRules" in data:
        return data["EnabledPreferenceRules"]
    if isinstance(data, dict) and "EnabledPreferenceRules" not in data:
        return None
    return data


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="spotlight-rules.py", description=__doc__)
    parser.add_argument("--list", required=True, help="lib/spotlight-apps.list")
    parser.add_argument("--plist", default="", help="defaults export of com.apple.Spotlight")
    parser.add_argument("--json", default="", help="rules JSON, for tests")
    args = parser.parse_args(argv)
    try:
        apps = load_apps(args.list)
        if args.json:
            rules: Any = json.loads(args.json)
        elif args.plist:
            rules = rules_from_plist(args.plist)
            if rules is None:
                emit(
                    "warn",
                    "EnabledPreferenceRules is not set, so Spotlight app results"
                    " could not be checked",
                )
                return 0
        else:
            emit("warn", "no Spotlight preferences were passed to the check")
            return 0
        status, message = judge(rules, apps)
        emit(status, message)
        return 0
    except Exception as exc:  # noqa: BLE001 - report, don't crash the check
        emit("warn", f"could not compare Spotlight results ({exc})")
        return 0


if __name__ == "__main__":
    sys.exit(main())
