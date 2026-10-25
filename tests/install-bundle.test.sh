#!/usr/bin/env bash
#
# install.sh's Brewfile failure: a partial install names the missing entries
# and points at brewsync. It does not open the App Store. The retry is
# `brew install`, not another `brew bundle install`. This does not execute
# install.sh (it refuses to run off Darwin, and on Darwin it would change
# the machine).
# Run: ./tests/install-bundle.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$DIR/install.sh"
HELPER="$DIR/lib/brew-bundle.sh"

pass=0
fail=0
eq() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
has() {
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n' "$1" "$2" ;; esac
}
miss() {
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n' "$1" "$2" ;;
    *) pass=$((pass + 1)) ;; esac
}

src="$(cat "$INSTALL")"
helper="$(cat "$HELPER")"
# shellcheck disable=SC2016  # needles are source text, compared literally
has "delegates the Brewfile to the helper" 'scripts/brew-bundle-install.sh' "$src"
# shellcheck disable=SC2016
has "checks the Brewfile after install" 'brew bundle check --no-upgrade --file "$file"' "$helper"
has "partial failure points at brewsync" 'run brewsync' "$src"
miss "generic some-entries message is gone" 'some Brewfile entries did not install' "$src$helper"
miss "does not open the App Store" 'macappstore://' "$src"
# shellcheck disable=SC2016
miss "does not retry brew bundle install" 'brew bundle install --file' "$src$helper"
has "retries a cask with brew install" 'brew install --cask' "$helper"
miss "does not call mas account" 'mas account' "$src"
miss "does not ask for App Store sign-in" 'App Store sign-in' "$src"

printf 'install-bundle tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
