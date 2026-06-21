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

# The Dock app list lives in lib/dock-apps.list (one "Display name | path" per line;
# see that file's header for details). Loaded so the list is a single source of truth
# shared with check.sh. Blank/# lines are skipped by the read loops.
APPS="$(<"$DOTDIR/lib/dock-apps.list")"

list_apps() {
  local n=0 name path
  while IFS='|' read -r name path; do
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
while IFS='|' read -r name path; do
  case "$name" in ''|'#'*) continue ;; esac
  path="${path/@HOME@/$HOME}"
  # Expand the one globbed path (WhatsApp); literal paths pass through unchanged.
  # shellcheck disable=SC2086  # intentional: unquoted $path lets the glob expand to its single match
  case "$path" in
    *'*'*) set -- $path; path="$1" ;;
  esac
  if [ -e "$path" ]; then
    dockutil --add "$path" --no-restart >/dev/null
    echo "  added $name"
  else
    echo "  [skip] not installed: $name"
  fi
done <<< "$APPS"

killall Dock || true
echo "✅ Dock set."
