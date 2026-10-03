#!/usr/bin/env python3
"""Compare Dock "Assign To" desktop pins against lib/desktop-bindings.list.

Read-only. Prints one line per app as  ok|msg  or  bad|msg  (or warn|msg).
macOS keeps pins in com.apple.spaces `app-bindings` (lowercased bundle id -> Space
UUID). Desktop 1 of the main display has an empty UUID, so a binding of "" means
Desktop 1; a missing key means "None". Full-screen Spaces are skipped when numbering.
"""
import plistlib
import subprocess
import sys


def main(list_path: str) -> int:
    try:
        raw = subprocess.run(["defaults", "export", "com.apple.spaces", "-"],
                             capture_output=True, check=True).stdout
        prefs = plistlib.loads(raw)
    except Exception as exc:  # noqa: BLE001 - report, don't crash check.sh
        print(f"warn|could not read com.apple.spaces ({exc})")
        return 0

    bindings = {k.lower(): v for k, v in (prefs.get("app-bindings") or {}).items()}
    monitors = (prefs.get("SpacesDisplayConfiguration", {})
                .get("Management Data", {}).get("Monitors", []))
    main_mon = next((m for m in monitors if m.get("Display Identifier") == "Main"), None)
    if main_mon is None:
        main_mon = next((m for m in monitors if m.get("Spaces")), {})
    desktops = [s for s in main_mon.get("Spaces", []) if s.get("type", 0) == 0]
    uuid_to_n = {(s.get("uuid") or ""): i for i, s in enumerate(desktops, 1)}

    for line in open(list_path, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, bundle, want = (p.strip() for p in line.split("|"))
        key = bundle.lower()
        if key not in bindings:
            have = "none"
        else:
            n = uuid_to_n.get(bindings[key] or "")
            have = str(n) if n else f"unknown desktop {bindings[key] or '(empty)'}"
        label = (lambda d: "None" if d == "none" else f"Desktop {d}")
        if have == want:
            print(f"ok|{name} assigned to {label(want)}")
        else:
            shown = have if have.startswith("unknown") else label(have)
            print(f"bad|{name} assigned to {shown} (expected {label(want)})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
