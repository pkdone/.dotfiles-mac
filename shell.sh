#!/usr/bin/env bash
#
# shell.sh — make Homebrew's fish the login shell (idempotent; safe to re-run).
#
# Each step is guarded so a correctly-set-up machine is a pure no-op (no sudo, no chsh):
#   1. Ensure fish's path is listed in /etc/shells (append once; needs sudo).
#   2. Set it as the login shell via chsh (only if not already).
#
# Flags:
#   --dry-run    Show what would happen; make no changes (no sudo, no chsh).
#   -h, --help   Show usage.
#
set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      cat <<'USAGE'
Usage: shell.sh [--dry-run]
  Make Homebrew fish the login shell (idempotent). Uses sudo + chsh interactively
  only when a change is actually needed; an already-configured machine is a no-op.
  --dry-run    Show what would happen; make no changes.
  -h, --help   Show this help.
USAGE
      exit 0 ;;
    *) echo "Unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

FISH="$(brew --prefix 2>/dev/null)/bin/fish"
if [ ! -x "$FISH" ]; then
  echo "fish not found at $FISH — install it first (it's in the Brewfile; run install.sh)." >&2
  exit 1
fi

# 1. /etc/shells must list fish before chsh will accept it.
if grep -qxF "$FISH" /etc/shells; then
  echo "ok      /etc/shells already lists $FISH"
elif [ "$DRY_RUN" = 1 ]; then
  echo "would   append $FISH to /etc/shells (via sudo)"
else
  echo "change  appending $FISH to /etc/shells (sudo)"
  echo "$FISH" | sudo tee -a /etc/shells >/dev/null
fi

# 2. Login shell -> fish (only if it differs).
cur_shell="$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')"
if [ "$cur_shell" = "$FISH" ]; then
  echo "ok      login shell already $FISH"
elif [ "$DRY_RUN" = 1 ]; then
  echo "would   chsh -s $FISH  (current: ${cur_shell:-unknown})"
else
  echo "change  chsh -s $FISH"
  chsh -s "$FISH"
fi

echo "Done."
