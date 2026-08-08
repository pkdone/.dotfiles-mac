#!/usr/bin/env bash
#
# handlers.sh — set URL-scheme default apps from lib/url-handlers.list (idempotent).
# Needs `duti` from the Brewfile. Used to keep mailto out of Apple Mail (Chrome instead).
#
# Flags:
#   --dry-run    Show what would change; make no changes.
#   --list       Print the managed handlers table.
#   -h, --help   Show usage.
#
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="$DOTDIR/lib/url-handlers.list"
DRY_RUN=0
LIST_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --list)    LIST_ONLY=1 ;;
    -h|--help)
      cat <<'USAGE'
Usage: handlers.sh [--dry-run] [--list]
  Apply URL-scheme handlers from lib/url-handlers.list via duti (idempotent).
  --dry-run    Show what would change; make no changes.
  --list       Print the managed handlers and exit.
  -h, --help   Show this help.
USAGE
      exit 0 ;;
    *) echo "Unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

[ -r "$LIST" ] || { echo "Error: required file not found: $LIST" >&2; exit 1; }

if [ "$LIST_ONLY" = 1 ]; then
  printf '| Scheme | Bundle ID |\n|------|------|\n'
  while IFS='|' read -r scheme bundle; do
    case "$scheme" in ''|'#'*) continue ;; esac
    # Intentional markdown backticks in --list table output.
    # shellcheck disable=SC2016
    printf '| `%s` | `%s` |\n' "$scheme" "$bundle"
  done < "$LIST"
  exit 0
fi

if ! command -v duti >/dev/null 2>&1; then
  echo "Error: duti not installed — run brew bundle / brewsync first." >&2
  exit 1
fi

changed=0
while IFS='|' read -r scheme bundle; do
  case "$scheme" in ''|'#'*) continue ;; esac
  cur="$(duti -d "$scheme" 2>/dev/null || true)"
  if [ "$cur" = "$bundle" ]; then
    echo "ok      $scheme -> $bundle"
  elif [ "$DRY_RUN" = 1 ]; then
    echo "would   $scheme: ${cur:-unset} -> $bundle"
  else
    echo "change  $scheme: ${cur:-unset} -> $bundle"
    duti -s "$bundle" "$scheme"
    changed=1
  fi
done < "$LIST"

if [ "$DRY_RUN" = 1 ]; then
  echo "Dry run complete."
elif [ "$changed" = 0 ]; then
  echo "No handler changes."
else
  echo "Done."
fi
