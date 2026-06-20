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

# "Display name | app path" — order is the left-to-right Dock order.
# WhatsApp's bundle name carries a hidden left-to-right mark (U+200E), so its
# path is a glob; it contains no spaces, so it expands cleanly at add time.
# @HOME@ is replaced with $HOME at runtime.
APPS='
Slack|/Applications/Slack.app
WhatsApp|/Applications/*WhatsApp.app
Granola|/Applications/Granola.app
Google Chrome|/Applications/Google Chrome.app
Claude|/Applications/Claude.app
ChatGPT|/Applications/ChatGPT.app
Gemini|/Applications/Gemini.app
Ghostty|/Applications/Ghostty.app
CotEditor|/Applications/CotEditor.app
Cursor|/Applications/Cursor.app
Cursor Nightly|/Applications/Cursor Nightly.app
Spotify|/Applications/Spotify.app
YouTube Music|@HOME@/Applications/Chrome Apps.localized/YouTube Music.app
'

list_apps() {
  local n=0 name path
  while IFS='|' read -r name path; do
    [ -z "$name" ] && continue
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
  [ -z "$name" ] && continue
  path="${path/@HOME@/$HOME}"
  # Expand the one globbed path (WhatsApp); literal paths pass through unchanged.
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
