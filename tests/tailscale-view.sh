#!/usr/bin/env bash
#
# Run a command in a view of /Applications/Tailscale.app.
#
#   tests/tailscale-view.sh absent -- tests/run-all.sh
#   tests/tailscale-view.sh installed -- tests/run-all.sh
#
# installed makes [ -d /Applications/Tailscale.app ] true. absent makes it
# false. Nothing is created on the host. Linux does this with a small
# stat/lstat interposer (tests/tailscale-view-stat.c), so the suite still
# runs as the current user. macOS uses the real bundle when it is installed,
# and sandbox-exec denies reads of it for absent.
#
# The interposer reads TAILSCALE_APP_VIEW, not TAILSCALE_VIEW. run-all.sh
# assigns TAILSCALE_VIEW="" at startup, and that empty value stays exported
# into the workers. Sharing the name made --tailscale installed a no-op.
#
# The interposer does not change access(2). A check that only stats the
# bundle sees an install; it does not execute a binary that is not there.
# Login items, defaults, and mdfind are still the host's unless the command
# stubs them. The Tailscale tests do.
#
# Bash 3.2-safe. Does not change the machine outside this process.
#
set -uo pipefail

die() {
  printf 'tests/tailscale-view.sh: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: tests/tailscale-view.sh absent|installed -- command [args...]
Run command where /Applications/Tailscale.app is missing (absent) or present
(installed). tests/run-all.sh --tailscale calls this.
EOF
}

so=""

cleanup() {
  if [ -n "$so" ]; then
    rm -f "$so"
    so=""
  fi
}

enter_preload() { # view
  local view="$1" dir src
  shift
  dir="$(cd "$(dirname "$0")" && pwd)"
  src="$dir/tailscale-view-stat.c"
  [ -f "$src" ] || die "missing $src"
  command -v gcc >/dev/null 2>&1 || die "gcc is required to build the Tailscale view"
  so="$(mktemp "${TMPDIR:-/tmp}/tailscale-view.XXXXXX")" || die "mktemp failed"
  rm -f "$so"
  so="$so.so"
  trap cleanup EXIT
  gcc -shared -fPIC -Wall -Wextra -o "$so" "$src" -ldl || die "could not build $src"
  # run-all.sh assigns TAILSCALE_VIEW="" and the workers inherit that. The
  # interposer must still see the bundle after that assignment.
  if ! env TAILSCALE_VIEW=installed TAILSCALE_APP_VIEW="$view" \
    LD_PRELOAD="$so${LD_PRELOAD:+:$LD_PRELOAD}" \
    /bin/bash -s -- "$view" <<'EOS'
TAILSCALE_VIEW=""
/bin/bash -s -- "$1" <<'INNER'
if [ "$1" = installed ]; then
  test -d /Applications/Tailscale.app
else
  test ! -d /Applications/Tailscale.app
fi
INNER
EOS
  then
    die "Tailscale view did not apply after TAILSCALE_VIEW was cleared"
  fi
  TAILSCALE_APP_VIEW="$view" LD_PRELOAD="$so${LD_PRELOAD:+:$LD_PRELOAD}" "$@"
  rc=$?
  cleanup
  trap - EXIT
  return "$rc"
}

enter_darwin() {
  local view="$1"
  shift
  case "$view" in
    installed)
      if [ -d /Applications/Tailscale.app ]; then
        RUN_ALL_INSIDE_TAILSCALE=installed exec "$@"
      fi
      die "this Mac has no /Applications/Tailscale.app; Linux can simulate it"
      ;;
    absent)
      if [ ! -e /Applications/Tailscale.app ]; then
        RUN_ALL_INSIDE_TAILSCALE=absent exec "$@"
      fi
      if ! command -v sandbox-exec >/dev/null 2>&1; then
        die "cannot hide /Applications/Tailscale.app (sandbox-exec is missing)"
      fi
      # stat of the bundle fails, so [ -d ] and [ -x ] are false. mdfind's
      # index is separate; the Tailscale tests stub mdfind.
      RUN_ALL_INSIDE_TAILSCALE=absent exec sandbox-exec -p '(version 1)
(allow default)
(deny file-read-data file-read-metadata
  (subpath "/Applications/Tailscale.app"))' "$@"
      ;;
  esac
  die "view must be absent or installed"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

view="${1:-}"
case "$view" in
  absent|installed) ;;
  *) die "view must be absent or installed (try --help)" ;;
esac
shift
if [ "${1:-}" = "--" ]; then
  shift
fi
[ "$#" -gt 0 ] || die "missing command"

case "$(uname -s)" in
  Darwin)
    enter_darwin "$view" "$@"
    ;;
  Linux)
    # No bundle on disk: absent is the normal filesystem.
    if [ "$view" = absent ] && [ ! -e /Applications/Tailscale.app ]; then
      RUN_ALL_INSIDE_TAILSCALE=absent exec "$@"
    fi
    enter_preload "$view" "$@"
    exit $?
    ;;
  *)
    die "unsupported system $(uname -s)"
    ;;
esac
