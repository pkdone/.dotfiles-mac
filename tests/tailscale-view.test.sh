#!/usr/bin/env bash
#
# --tailscale installed must still show /Applications/Tailscale.app to a
# worker. run-all.sh assigns TAILSCALE_VIEW="" at startup, and that empty
# value stays exported when the view script passed the same name in.
# --check-view asks a child of that re-invoked runner, which is the same
# environment the suites run in. absent must not see the bundle.
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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# This file also runs inside a view. Drop the Linux interposer so the checks
# below start from the real filesystem. Unsetting variables does not leave a
# macOS absent sandbox: sandbox-exec is inherited by every child, and macOS
# cannot invent /Applications/Tailscale.app when this process cannot see it.
clean() {
  env -u LD_PRELOAD -u DYLD_INSERT_LIBRARIES -u TAILSCALE_APP_VIEW \
    -u TAILSCALE_VIEW -u RUN_ALL_INSIDE_TAILSCALE "$@"
}

# Linux simulates either view. macOS shows "installed" only when this process
# can already stat the bundle (the real app, not hidden by an absent sandbox).
if [ "$(uname -s)" != Darwin ] || [ -d /Applications/Tailscale.app ]; then
  installed="$(clean "$RUN" --tailscale installed --check-view 2>"$tmp/installed.err")"
  installed_rc=$?
  eq "installed view exits 0" 0 "$installed_rc"
  eq "a worker sees Tailscale.app when the view is installed" present "$installed"
  eq "installed view stderr stays empty" "" "$(cat "$tmp/installed.err")"
fi

absent="$(clean "$RUN" --tailscale absent --check-view 2>"$tmp/absent.err")"
absent_rc=$?
eq "absent view exits 0" 0 "$absent_rc"
eq "a worker does not see Tailscale.app when the view is absent" absent "$absent"
eq "absent view stderr stays empty" "" "$(cat "$tmp/absent.err")"

printf 'tailscale-view tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
