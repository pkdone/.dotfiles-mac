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
trap 'brew_on_exit' EXIT

rc=0
brew_bundle_main "$@" || rc=$?
exit "$rc"
