#!/usr/bin/env bash
# Load a per-user LaunchAgent plist into the gui/<uid> domain. Idempotent.
# Used by install.sh (--reload: pick up plist changes) and `check.sh --fix`
# (default: bootstrap only if the agent isn't loaded; never unloads a loaded one).
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: load-launchagent.sh [--reload] [--check] PLIST
  (default)  Bootstrap PLIST into gui/<uid> if its label isn't loaded yet.
  --reload   Boot out the loaded agent first, then bootstrap (install.sh).
  --check    Exit 0 if loaded, 1 if not; change nothing.
The label is the plist's file name without .plist.
USAGE
}

RELOAD=0; CHECK=0; PLIST=""
for arg in "$@"; do
  case "$arg" in
    --reload) RELOAD=1 ;;
    --check)  CHECK=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown argument: $arg (try --help)" >&2; exit 2 ;;
    *)  PLIST="$arg" ;;
  esac
done
if [ -z "$PLIST" ]; then usage >&2; exit 2; fi

LABEL="$(basename "$PLIST" .plist)"
DOMAIN="gui/$(id -u)"
is_loaded() { launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; }

if [ "$CHECK" = 1 ]; then
  if is_loaded; then echo "$LABEL loaded"; exit 0; fi
  echo "$LABEL not loaded"; exit 1
fi
if [ ! -f "$PLIST" ]; then
  echo "$LABEL: $PLIST missing" >&2
  exit 1
fi
if is_loaded; then
  if [ "$RELOAD" != 1 ]; then
    echo "$LABEL already loaded"
    exit 0
  fi
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
fi
if launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null; then
  echo "$LABEL loaded"
elif launchctl load -w "$PLIST" 2>/dev/null; then
  echo "$LABEL loaded (launchctl load -w)"
else
  echo "$LABEL: could not bootstrap — run: launchctl bootstrap $DOMAIN $PLIST" >&2
  exit 1
fi
