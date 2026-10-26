#!/usr/bin/env bash
#
# --tailscale installed must still show /Applications/Tailscale.app to a
# worker. run-all.sh assigns TAILSCALE_VIEW="" at startup, and that empty
# value stays exported when the view script passed the same name in.
# --check-view asks a child of that re-invoked runner.
#
# Do not start those checks from inside a view. On macOS the absent view is
# sandbox-exec, which every child inherits; unsetting variables does not
# leave it, and macOS cannot invent the bundle when this process cannot
# see it. The default suite (not already in a view) still runs the checks:
# Linux simulates both, and a Mac with the real app can too. A Mac with no
# Tailscale install only runs the absent check, which does not need the app.
# Run: ./tests/tailscale-view.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$DIR/tests/run-all.sh"

pass=0
fail=0
eq() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}

# Already inside a view. A nested installed check cannot escape a sandbox.
if [ -n "${RUN_ALL_INSIDE_TAILSCALE:-}" ] || [ -n "${TAILSCALE_APP_VIEW:-}" ]; then
  printf 'tailscale-view tests: already in a view, nested checks skipped\n'
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Drop a Linux interposer inherited from the environment. This is not a
# sandbox escape; that case returned above.
clean() {
  env -u LD_PRELOAD -u DYLD_INSERT_LIBRARIES -u TAILSCALE_APP_VIEW \
    -u TAILSCALE_VIEW -u RUN_ALL_INSIDE_TAILSCALE "$@"
}

view_check() { # label view expected
  local label="$1" view="$2" expected="$3" out rc err
  err="$tmp/$view.err"
  out="$(clean "$RUN" --tailscale "$view" --check-view 2>"$err")"
  rc=$?
  if [ "$rc" != 0 ]; then
    fail=$((fail + 1))
    printf 'FAIL: %s exits 0\n  exit: %s\n  stderr: [%s]\n' "$label" "$rc" "$(cat "$err")"
  else
    pass=$((pass + 1))
  fi
  eq "$label" "$expected" "$out"
}

# macOS installed is the real bundle. Skip it when that bundle is not
# visible, including a Mac that has never had Tailscale installed.
if [ "$(uname -s)" != Darwin ] || [ -d /Applications/Tailscale.app ]; then
  view_check "a worker sees Tailscale.app when the view is installed" \
    installed present
fi
view_check "a worker does not see Tailscale.app when the view is absent" \
  absent absent

printf 'tailscale-view tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
