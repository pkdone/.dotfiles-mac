#!/usr/bin/env bash
#
# dock.sh — pin a fixed, ordered set of apps to the Dock (idempotent).
#
# Rebuilds the Dock's app section: clears it, then adds each app below in order.
# Safe to re-run — it converges to exactly this layout, then restarts the Dock.
# Requires dockutil (in the Brewfile).
#
set -euo pipefail

if ! command -v dockutil >/dev/null 2>&1; then
  echo "dockutil not found — install it first (it's in the Brewfile)." >&2
  exit 1
fi

# WhatsApp's bundle name carries a hidden left-to-right mark (U+200E),
# so resolve it with a glob instead of a literal path.
whatsapp=(/Applications/*WhatsApp.app)

apps=(
  "/Applications/Slack.app"
  "${whatsapp[0]}"
  "/Applications/Granola.app"
  "/Applications/Google Chrome.app"
  "/Applications/Claude.app"
  "/Applications/ChatGPT.app"
  "/Applications/Gemini.app"
  "/Applications/Ghostty.app"
  "/Applications/CotEditor.app"
  "/Applications/Cursor.app"
  "/Applications/Cursor Nightly.app"
  "/Applications/Spotify.app"
  "$HOME/Applications/Chrome Apps.localized/YouTube Music.app"
)

echo "🧹 Clearing the Dock..."
dockutil --remove all --no-restart >/dev/null

echo "📌 Pinning apps in order..."
for app in "${apps[@]}"; do
  if [ -e "$app" ]; then
    dockutil --add "$app" --no-restart >/dev/null
    echo "  added $(basename "$app")"
  else
    echo "  [skip] not installed: $app"
  fi
done

killall Dock || true
echo "✅ Dock set."
