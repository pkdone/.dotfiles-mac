#!/usr/bin/env python3
"""Summarise recent kernel panics and app crashes from DiagnosticReports (read-only).

Looks in /Library/Logs/DiagnosticReports and ~/Library/Logs/DiagnosticReports (plus
one level of subfolders, e.g. Retired/) for files modified in the last DAYS days:
  panics:  *.panic, or .ips reports with bug_type 210 (panic-full-*.ips)
  crashes: .ips reports with bug_type 309, grouped by app_name. ExcUserFault_* reports
           share that bug_type but are non-fatal "user fault" diagnostics (the process
           keeps running), so they're counted separately as faults, not crashes.

Usage: crash-reports.py [DAYS]   (default 7)
Output, one record per line:
  panic|<file name>
  crash|<app>|<count>          (most first)
  totals|<panics>|<crashes>|<faults>|<unreadable>
"""
from __future__ import annotations

import collections
import json
import os
import sys
import time

DIRS = ["/Library/Logs/DiagnosticReports",
        os.path.expanduser("~/Library/Logs/DiagnosticReports")]


def header(path: str) -> dict:
    with open(path, encoding="utf-8", errors="replace") as f:
        line = f.readline(65536)
    try:
        h = json.loads(line)
    except ValueError:
        return {}
    return h if isinstance(h, dict) else {}


def main() -> int:
    days = float(sys.argv[1]) if len(sys.argv) > 1 else 7.0
    cutoff = time.time() - days * 86400
    panics, crashes = [], collections.Counter()
    faults = unreadable = 0
    for base in DIRS:
        for sub in ("", "Retired"):
            d = os.path.join(base, sub) if sub else base
            try:
                names = os.listdir(d)
            except OSError:
                continue
            for name in names:
                if not (name.endswith(".ips") or name.endswith(".panic")):
                    continue
                p = os.path.join(d, name)
                try:
                    if os.stat(p).st_mtime < cutoff:
                        continue
                    if name.endswith(".panic"):
                        panics.append(name)
                        continue
                    h = header(p)
                except OSError:
                    unreadable += 1
                    continue
                bug = str(h.get("bug_type", ""))
                if bug == "210" or name.startswith("panic-"):
                    panics.append(name)
                elif bug == "309":
                    if name.startswith("ExcUserFault_"):
                        faults += 1
                    else:
                        crashes[h.get("app_name") or h.get("name") or name.split("-")[0]] += 1
    for name in sorted(set(panics)):
        print(f"panic|{name}")
    for app, n in crashes.most_common():
        print(f"crash|{str(app).replace('|', '/')}|{n}")
    print(f"totals|{len(set(panics))}|{sum(crashes.values())}|{faults}|{unreadable}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
