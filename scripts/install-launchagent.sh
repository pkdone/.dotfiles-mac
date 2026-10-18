#!/usr/bin/env bash
# Render a repo LaunchAgent plist into ~/Library/LaunchAgents.
#
# launchd does not expand ~ or $HOME. WatchPaths in the repo plists use the
# @HOME@ placeholder; this script writes a regular file with $HOME filled in.
# The installed plist is never a symlink: writing through a symlink would edit
# the repo copy, and a symlink would leave @HOME@ unexpanded for launchd.
#
# Used by install.sh and macconfig-check.sh (--check is read-only; --fix writes
# when the installed file differs, then bootout/bootstraps via load-launchagent.sh).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage: install-launchagent.sh --check|--write LABEL

  Render launchagents/LABEL.plist (@HOME@ -> $HOME) and compare it to
  ~/Library/LaunchAgents/LABEL.plist.

  --check   Exit 0 if the installed file is a regular file and matches.
            Exit 1 if it is missing, a symlink, or different. Change nothing.
  --write   Write the rendered plist when it differs. A symlink is removed
            first (the repo file is not edited). Prints "unchanged" or "updated".
USAGE
}

MODE=""
LABEL=""
for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --write) MODE="write" ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown argument: $arg (try --help)" >&2; exit 2 ;;
    *)
      if [ -n "$LABEL" ]; then
        echo "Unexpected extra argument: $arg" >&2
        exit 2
      fi
      LABEL="$arg"
      ;;
  esac
done
if [ -z "$MODE" ] || [ -z "$LABEL" ]; then
  usage >&2
  exit 2
fi
case "$LABEL" in
  *[!A-Za-z0-9._-]*) echo "Invalid LaunchAgent label: $LABEL" >&2; exit 2 ;;
esac
if [ -z "${HOME:-}" ] || [ "$HOME" = / ]; then
  echo "HOME is unset; refusing to render a LaunchAgent" >&2
  exit 2
fi

src="$REPO/launchagents/${LABEL}.plist"
dest="${HOME}/Library/LaunchAgents/${LABEL}.plist"
if [ ! -f "$src" ]; then
  echo "repo plist missing: launchagents/${LABEL}.plist" >&2
  exit 2
fi

tmp=""
cleanup() {
  if [ -n "${tmp}" ]; then
    rm -f "$tmp"
  fi
}
trap cleanup EXIT
tmp="$(mktemp "${TMPDIR:-/tmp}/launchagent.XXXXXX")"

render() {
  local line home="$HOME"
  while IFS= read -r line || [ -n "$line" ]; do
    printf '%s\n' "${line//@HOME@/$home}"
  done < "$src"
}
render >"$tmp"

if grep -q '@HOME@' "$tmp"; then
  echo "rendered plist still contains @HOME@ (HOME=$HOME)" >&2
  exit 2
fi

status_line() {
  if [ -L "$dest" ]; then
    echo "installed plist is a symlink — --fix replaces it with a rendered copy and reloads (bootout/bootstrap)"
    return 1
  fi
  if [ ! -f "$dest" ]; then
    echo "installed plist missing — --fix writes it and bootstraps the agent"
    return 1
  fi
  if ! cmp -s "$tmp" "$dest"; then
    echo "installed plist differs from repo — --fix rewrites it and reloads (bootout/bootstrap)"
    return 1
  fi
  echo "WatchPaths symbolichotkeys, ThrottleInterval 10"
  return 0
}

if [ "$MODE" = check ]; then
  if status_line; then
    exit 0
  fi
  exit 1
fi

# --write. rm before mv so a symlink is not followed into the repo file.
if [ -L "$dest" ] || [ ! -f "$dest" ] || ! cmp -s "$tmp" "$dest"; then
  mkdir -p "$(dirname "$dest")"
  rm -f "$dest"
  mv "$tmp" "$dest"
  tmp=""
  echo updated
else
  echo unchanged
fi
