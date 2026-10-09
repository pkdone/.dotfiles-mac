#!/usr/bin/env bash
#
# handlers.sh — set default apps from the repo lists (idempotent).
# Needs `duti` from the Brewfile.
#   lib/url-handlers.list   URL schemes (mailto → Chrome, so Apple apps don't claim them)
#   lib/file-handlers.list  Finder double-click extensions (CotEditor / Cursor), role all
#
# Flags:
#   --dry-run    Show what would change; make no changes.
#   --list       Print the managed handlers tables.
#   -h, --help   Show usage.
#
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="$DOTDIR/lib/url-handlers.list"
FILE_LIST="$DOTDIR/lib/file-handlers.list"
DRY_RUN=0
LIST_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --list)    LIST_ONLY=1 ;;
    -h|--help)
      cat <<'USAGE'
Usage: handlers.sh [--dry-run] [--list]
  Apply URL-scheme handlers (lib/url-handlers.list) and Finder file handlers
  (lib/file-handlers.list) via duti (idempotent). File handlers use
  `duti -s <bundle-id> .<ext> all`.
  --dry-run    Show what would change; make no changes.
  --list       Print the managed handlers and exit.
  -h, --help   Show this help.
USAGE
      exit 0 ;;
    *) echo "Unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

[ -r "$LIST" ] || { echo "Error: required file not found: $LIST" >&2; exit 1; }
[ -r "$FILE_LIST" ] || { echo "Error: required file not found: $FILE_LIST" >&2; exit 1; }

if [ "$LIST_ONLY" = 1 ]; then
  printf '| Scheme | Bundle ID |\n|------|------|\n'
  while IFS='|' read -r scheme bundle; do
    case "$scheme" in ''|'#'*) continue ;; esac
    # Intentional markdown backticks in --list table output.
    # shellcheck disable=SC2016
    printf '| `%s` | `%s` |\n' "$scheme" "$bundle"
  done < "$LIST"
  printf '\n| Extension | App | Bundle ID |\n|------|------|------|\n'
  while IFS='|' read -r ext app bundle _flag; do
    case "$ext" in ''|'#'*) continue ;; esac
    # shellcheck disable=SC2016
    printf '| `%s` | `%s` | `%s` |\n' "$ext" "$app" "$bundle"
  done < "$FILE_LIST"
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

# File extensions share lib/file-handlers.py with macconfig-check.sh --fix, so the
# duti -x / duti -s rules can't drift between bootstrap and the drift check.
apply_file_handlers() {
  local file_py file_out file_rc status ext msg
  local cmd
  # shellcheck source=lib/defaults-lib.sh disable=SC1091
  . "$DOTDIR/lib/defaults-lib.sh"
  file_py="$(dot_python || true)"
  if [ -z "$file_py" ]; then
    echo "Error: python3 not found — can't apply lib/file-handlers.list" >&2
    return 1
  fi
  cmd=("$file_py" "$DOTDIR/lib/file-handlers.py" --apply)
  if [ "$DRY_RUN" = 1 ]; then
    cmd+=(--dry-run)
  fi
  cmd+=("$FILE_LIST")
  file_rc=0
  if file_out="$("${cmd[@]}" 2>&1)"; then
    file_rc=0
  else
    file_rc=$?
  fi
  while IFS='|' read -r status ext msg; do
    if [ -z "$status" ]; then
      continue
    fi
    case "$status" in
      ok)  printf 'ok      %s\n' "$msg" ;;
      chg)
        printf 'change  %s\n' "$msg"
        changed=1 ;;
      dry) printf 'would   %s\n' "$msg" ;;
      info) printf 'info    %s\n' "$msg" ;;
      *)   printf 'error   %s\n' "${msg:-$status}" >&2 ;;
    esac
  done <<< "$file_out"
  return "$file_rc"
}
apply_file_handlers

if [ "$DRY_RUN" = 1 ]; then
  echo "Dry run complete."
elif [ "$changed" = 0 ]; then
  echo "No handler changes."
else
  echo "Done."
fi
