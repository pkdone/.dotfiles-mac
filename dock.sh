#!/usr/bin/env bash
#
# dock.sh — pin a fixed, ordered set of apps to the Dock, then apply the
# Desktop assignments (idempotent).
#
# With no arguments: clears the Dock's app section and re-adds each app below
# in order, restarts the Dock, then applies lib/desktop-bindings.list through
# lib/safe-fixers.sh — the same helper macconfig-check.sh --fix uses. That
# writes com.apple.spaces app-bindings and restarts the Dock only if a pin
# changed. Safe to re-run — it converges to exactly this layout. Requires
# dockutil (in the Brewfile) for the app section.
#
# Flags:
#   --list       Print the Dock apps and the Desktop pins; change nothing.
#   --dry-run    Same preview as --list (no dockutil, no preference writes).
#   -h, --help   Show usage.
#
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/safe-fixers.sh disable=SC1091
. "$DOTDIR/lib/safe-fixers.sh"

# Fail early with a clear message if a required data file is missing.
require_file() { [ -r "$1" ] || { echo "Error: required file not found: $1" >&2; exit 1; }; }
require_file "$DOTDIR/lib/dock-apps.list"
require_file "$DOTDIR/lib/desktop-bindings.list"

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

# Print desktop-bindings.py lines as plain sentences. Returns the helper status.
# --dry-run (and any other helper args) are passed through.
run_desktop_pins() {
  local out="" rc=0 status="" bundle="" msg=""
  if out="$(safe_apply_desktops "$@" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  while IFS='|' read -r status bundle msg; do
    [ -n "${status:-}" ] || continue
    printf '  %s\n' "${msg:-$bundle}"
  done <<< "$out"
  return "$rc"
}

usage() {
  cat <<'USAGE'
Usage: dock.sh [--list | --dry-run]
  --list       Print the Dock apps and the Desktop pins; change nothing.
  --dry-run    Same preview as --list (no dockutil, no preference writes).
  -h, --help   Show this help.

With no arguments, dock.sh rebuilds the Dock's app section to exactly these
apps, in order (idempotent), restarts the Dock, then applies
lib/desktop-bindings.list (com.apple.spaces app-bindings). The Dock is
restarted again only if a Desktop pin changed.
USAGE
}

PREVIEW=0
case "${1:-}" in
  --list|--dry-run) PREVIEW=1 ;;
  -h|--help)        usage; exit 0 ;;
  "")               : ;;
  *)                echo "Unknown argument: $1 (try --help)" >&2; exit 2 ;;
esac

if [ "$PREVIEW" = 1 ]; then
  list_apps
  echo ""
  echo "Desktop pins (lib/desktop-bindings.list) — preview, nothing is changed:"
  # A missing Space is reported and not created. The preview itself still
  # succeeds: it did not write anything.
  run_desktop_pins --dry-run || true
  exit 0
fi

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

echo ""
echo "🖥  Desktop pins (lib/desktop-bindings.list)..."
run_desktop_pins
