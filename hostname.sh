#!/usr/bin/env bash
#
# hostname.sh — set the machine's host names (idempotent; needs sudo to change).
#
# Sets HostName, LocalHostName and ComputerName to $DESIRED, each only if it differs,
# then flushes the DNS cache if anything changed. Re-running on a correct machine is a
# pure no-op and uses no sudo.
#
# Flags:
#   --dry-run    Show what would change; make no changes (no sudo).
#   -h, --help   Show usage.
#
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Hostname is defined once in lib/hostname (shared with check.sh).
DESIRED="$(awk '$1 !~ /^#/ && NF {print $1; exit}' "$DOTDIR/lib/hostname")"
[ -n "$DESIRED" ] || { echo "Error: no hostname found in $DOTDIR/lib/hostname" >&2; exit 1; }

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      cat <<'USAGE'
Usage: hostname.sh [--dry-run]
  Set HostName / LocalHostName / ComputerName (idempotent). Uses sudo interactively
  only when a name actually needs changing; an already-configured machine is a no-op.
  --dry-run    Show what would change; make no changes.
  -h, --help   Show this help.
USAGE
      exit 0 ;;
    *) echo "Unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

changed=0
for which in HostName LocalHostName ComputerName; do
  cur="$(scutil --get "$which" 2>/dev/null || true)"
  if [ "$cur" = "$DESIRED" ]; then
    echo "ok      $which already $DESIRED"
  elif [ "$DRY_RUN" = 1 ]; then
    echo "would   set $which: ${cur:-unset} -> $DESIRED (via sudo)"
  else
    echo "change  set $which -> $DESIRED (sudo)"
    sudo scutil --set "$which" "$DESIRED"
    changed=1
  fi
done

if [ "$changed" = 1 ]; then
  echo "change  flushing DNS cache"
  dscacheutil -flushcache
else
  echo "No name changes; DNS cache not flushed."
fi

echo "Done."
