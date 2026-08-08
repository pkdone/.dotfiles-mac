#!/usr/bin/env bash
#
# prune-apps.sh — remove apps listed in lib/unwanted-apps.list (idempotent).
# Prefers `mas uninstall` when a Mac App Store id is set; falls back to `rm -rf`
# on the app path. Uses sudo when a TTY is available, otherwise a macOS
# administrator-privileges dialog (osascript) so agent/non-TTY runs still work.
# Re-running when already gone is a no-op.
#
# Flags:
#   --dry-run    Show what would be removed; make no changes (no sudo).
#   --list       Print the unwanted-apps table.
#   -h, --help   Show usage.
#
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="$DOTDIR/lib/unwanted-apps.list"
DRY_RUN=0
LIST_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --list)    LIST_ONLY=1 ;;
    -h|--help)
      cat <<'USAGE'
Usage: prune-apps.sh [--dry-run] [--list]
  Remove apps listed in lib/unwanted-apps.list (idempotent).
  --dry-run    Show what would be removed; make no changes.
  --list       Print the unwanted apps and exit.
  -h, --help   Show this help.
USAGE
      exit 0 ;;
    *) echo "Unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

[ -r "$LIST" ] || { echo "Error: required file not found: $LIST" >&2; exit 1; }

trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

# Run a shell command as root: sudo if possible, else macOS admin dialog.
run_as_root() {
  local cmd="$1"
  if sudo -n true 2>/dev/null; then
    sudo /bin/bash -lc "$cmd"
  elif [ -t 0 ] && [ -t 1 ]; then
    sudo /bin/bash -lc "$cmd"
  else
    # Non-interactive shells (e.g. agent ExternalShell) can't prompt for a password.
    echo "Error: need an interactive terminal for sudo." >&2
    echo "       Re-run: ~/.dotfiles-mac/prune-apps.sh" >&2
    return 1
  fi
}


if [ "$LIST_ONLY" = 1 ]; then
  printf '| Name | Path | MAS id |\n|------|------|--------|\n'
  while IFS='|' read -r name path mas_id; do
    case "$name" in ''|'#'*) continue ;; esac
    name="$(trim "$name")"; path="$(trim "$path")"; mas_id="$(trim "${mas_id:-0}")"
    # Intentional markdown backticks in --list table output.
    # shellcheck disable=SC2016
    printf '| `%s` | `%s` | `%s` |\n' "$name" "$path" "$mas_id"
  done < "$LIST"
  exit 0
fi

removed=0
while IFS='|' read -r name path mas_id; do
  case "$name" in ''|'#'*) continue ;; esac
  name="$(trim "$name")"; path="$(trim "$path")"; mas_id="$(trim "${mas_id:-0}")"
  [ -n "$name" ] && [ -n "$path" ] || continue

  if [ ! -e "$path" ]; then
    echo "ok      $name already absent ($path)"
    continue
  fi

  if [ "$DRY_RUN" = 1 ]; then
    if [ -n "$mas_id" ] && [ "$mas_id" != "0" ]; then
      echo "would   remove $name ($path) via mas $mas_id"
    else
      echo "would   remove $name ($path)"
    fi
    continue
  fi

  if [ -n "$mas_id" ] && [ "$mas_id" != "0" ] && command -v mas >/dev/null 2>&1; then
    mas_bin="$(command -v mas)"
    echo "remove  $name via mas uninstall $mas_id (admin)"
    run_as_root "$mas_bin uninstall $mas_id"
  else
    echo "remove  $name via rm -rf ($path) (admin)"
    # Quote path for the nested shell.
    run_as_root "rm -rf $(printf '%q' "$path")"
  fi
  removed=1
done < "$LIST"

if [ "$DRY_RUN" = 1 ]; then
  echo "Dry run complete."
elif [ "$removed" = 0 ]; then
  echo "No apps to remove."
else
  echo "Done."
fi
