#!/usr/bin/env bash
#
# brew-bundle-install.sh — install the Brewfile, retry each miss once, and
# name whatever is still missing. install.sh and brewsync both call this.
# The run log is the caller's (install.sh, bootstrap.sh, or brewsync); this
# script does not open a second log file.
#
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/dotfiles-log.sh disable=SC1091
. "$DOTDIR/lib/dotfiles-log.sh"
# shellcheck source=../lib/brew-bundle.sh disable=SC1091
. "$DOTDIR/lib/brew-bundle.sh"

dotfiles_refuse_root "brew-bundle-install.sh"

# brew_bundle_main sets BREW_BUNDLE_HANDLED=1 before every return that finished
# a report. A crash (set -u, or a stop before that) leaves it at 0, so the
# exit trap can say the install stopped instead of pretending packages were named.
BREW_BUNDLE_HANDLED=0
brew_bundle_finished=0
# Invoked by the EXIT trap, including after set -u aborts the shell.
# shellcheck disable=SC2317
brew_bundle_exit() {
  local status=$?
  brew_on_exit || true
  if [ "${brew_bundle_finished:-0}" != 1 ]; then
    echo "Brewfile install stopped before it could finish." >&2
    exit 3
  fi
  exit "$status"
}
trap brew_bundle_exit EXIT

# Tests set DOTFILES_BREW_TRAP_PROBE=1 to trip set -u in this shell. A command
# substitution would only kill a subshell, and the || below would hide it.
# Normal runs leave the probe unset.
if [ "${DOTFILES_BREW_TRAP_PROBE:-}" = 1 ]; then
  # shellcheck disable=SC2154
  printf '%s\n' "$DOTFILES_BREW_TRAP_UNSET"
fi

rc=0
brew_bundle_main "$@" || rc=$?
if [ "${BREW_BUNDLE_HANDLED:-0}" = 1 ]; then
  brew_bundle_finished=1
fi
exit "$rc"
