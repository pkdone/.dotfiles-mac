#!/usr/bin/env bash
#
# dock.sh — pin a fixed, ordered set of apps to the Dock (idempotent).
#
# With no arguments: clears the Dock's app section and re-adds each app below
# in order, then restarts the Dock. Safe to re-run — it converges to exactly
# this layout. Requires dockutil (in the Brewfile).
#
# Flags:
#   --list       Print the Dock apps in order and exit (no changes; no dockutil needed).
#   -h, --help   Show usage.
#
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fail early with a clear message if a required data file is missing.
require_file() { [ -r "$1" ] || { echo "Error: required file not found: $1" >&2; exit 1; }; }
require_file "$DOTDIR/lib/dock-apps.list"

# The Dock app list lives in lib/dock-apps.list (one "Display name | path" per line,
# with an optional "manual:<step-id>" field; see that file's header). Loaded so the
# list is a single source of truth shared with macconfig-check.sh. Blank/# lines are
# skipped by the read loops. A manual-step app that is not on disk yet is skipped.
APPS="$(<"$DOTDIR/lib/dock-apps.list")"

list_apps() {
  local n=0 name path manual
  while IFS='|' read -r name path manual; do
    case "$name" in ''|'#'*) continue ;; esac
    n=$((n + 1))
    printf '%2d. %s\n' "$n" "$name"
  done <<< "$APPS"
}

usage() {
  cat <<'USAGE'
Usage: dock.sh [--list]
  --list       Print the Dock apps in order and exit (no changes; dockutil not required).
  -h, --help   Show this help.

With no arguments, dock.sh rebuilds the Dock's app section to exactly these
apps, in order (idempotent), and restarts the Dock.
USAGE
}

case "${1:-}" in
  --list)     list_apps; exit 0 ;;
  -h|--help)  usage; exit 0 ;;
  "")         : ;;
  *)          echo "Unknown argument: $1 (try --help)" >&2; exit 2 ;;
esac

if ! command -v dockutil >/dev/null 2>&1; then
  echo "dockutil not found — install it first (it's in the Brewfile)." >&2
  exit 1
fi

echo "🧹 Clearing the Dock..."
dockutil --remove all --no-restart >/dev/null

echo "📌 Pinning apps in order..."
while IFS='|' read -r name path manual; do
  case "$name" in ''|'#'*) continue ;; esac
  path="${path/@HOME@/$HOME}"
  # A path containing * is a glob; expand it to the first match. Literal paths pass through.
  # shellcheck disable=SC2086  # intentional: unquoted $path lets the glob expand to its single match
  case "$path" in
    *'*'*) set -- $path; path="$1" ;;
  esac
  if [ -e "$path" ]; then
    dockutil --add "$path" --no-restart >/dev/null
    echo "  added $name"
  elif [ -n "${manual:-}" ]; then
    echo "  [skip] $name is missing because the manual step hasn't been done (${manual#manual:})"
  else
    echo "  [skip] not installed: $name"
  fi
done <<< "$APPS"

killall Dock || true
echo "✅ Dock set."
