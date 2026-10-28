#!/usr/bin/env bash
# Clear the view each folder saved for itself, so every folder (the Desktop
# included) falls back to Finder's default view: Sort By Name from
# scripts/pin-finder-icon-view.sh. Finder keeps a folder's own view, icon
# positions included, in a .DS_Store file inside that folder. This deletes
# those files under $HOME and restarts Finder. Run on request only:
# macconfig --reset-folder-views [--dry-run]. --fix and the drift check never
# run it.
#
# Pruned, not walked: ~/Library (iCloud Drive, CloudStorage, app data),
# ~/.Trash, every hidden dot-directory (~/.cursor, .git trees), node_modules,
# and app / Photos / Music library bundles. -xdev stays on the home volume, so
# a network share or cloud mount under $HOME is skipped. Symlinks are not
# followed, and only regular files are removed. Unreadable folders are
# skipped quietly.
#
# Bash 3.2-safe (stock macOS bash).
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN="$DIR/scripts/pin-finder-icon-view.sh"
LOG="${HOME}/Library/Logs/com.pdone.reset-folder-views.log"
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: reset-folder-views.sh [--dry-run]

  Delete the .DS_Store files under your home folder (Desktop included) and
  restart Finder, so every folder uses the default view (Sort By Name).
  A folder's own view settings and icon positions are lost.

  Skipped: ~/Library, ~/.Trash, hidden folders (names starting with "."),
  node_modules, app and Photos/Music library bundles, other volumes mounted
  under your home folder, and symlinks.

  --dry-run  List what would be removed. Delete nothing, restart nothing.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done

ROOT="${HOME:-}"
ROOT="${ROOT%/}"
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
  echo "reset-folder-views: HOME is not a folder (${HOME:-unset})" >&2
  exit 1
fi

log() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || return 0
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true
}

show() { # path under $HOME, printed as ~/...
  case "$1" in
    "$ROOT"/*) printf '  ~/%s\n' "${1#"$ROOT"/}" ;;
    *) printf '  %s\n' "$1" ;;
  esac
}

# -H follows $HOME itself if it is a link, and nothing found below it.
list_ds_store() {
  find -H "$ROOT" -xdev \
    \( -path "$ROOT/Library" -o -path "$ROOT/.Trash" \
       -o \( -name '.?*' ! -path "$ROOT" \) \
       -o -name node_modules -o -name '*.app' \
       -o -name '*.photoslibrary' -o -name '*.musiclibrary' \) \
    -type d -prune \
    -o -type f -name .DS_Store -print0 2>/dev/null
}

found=0
removed=0
failed=0
while IFS= read -r -d '' f; do
  if [ ! -f "$f" ] || [ -L "$f" ]; then
    continue
  fi
  found=$((found + 1))
  if [ "$DRY_RUN" = 1 ]; then
    show "$f"
  elif rm -f -- "$f" 2>/dev/null && [ ! -e "$f" ]; then
    removed=$((removed + 1))
  else
    failed=$((failed + 1))
  fi
done < <(list_ds_store)

if [ "$DRY_RUN" = 1 ]; then
  if [ "$found" -eq 0 ]; then
    echo "No saved folder views under ~ (no .DS_Store files). Nothing would change."
  else
    echo "Would remove $found .DS_Store file(s) listed above, then restart Finder (dry-run)."
  fi
  exit 0
fi

msg="Removed $removed .DS_Store file(s) under ~"
[ "$failed" -eq 0 ] || msg="$msg; $failed could not be removed (permission), left alone"
killall Finder 2>/dev/null || true
echo "$msg. Finder restarted."
log "$msg"

if [ -x "$PIN" ] && ! "$PIN" --check >/dev/null 2>&1; then
  echo "Finder's default view is not Sort By Name yet. Run: macconfig --fix"
fi
exit 0
