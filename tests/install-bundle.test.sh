#!/usr/bin/env bash
#
# install.sh's Brewfile failure: a partial `brew bundle` warns and points at
# brewsync. It does not open the App Store or retry the install. This does not
# execute install.sh (it refuses to run off Darwin).
# Run: ./tests/install-bundle.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$DIR/install.sh"

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
# shellcheck disable=SC2016  # needles are source text, compared literally
has "checks the Brewfile after install" 'brew bundle check --file "$DOTFILES/Brewfile"' "$src"
has "keeps the partial-failure warning" 'some Brewfile entries did not install' "$src"
has "partial failure points at brewsync" 'run brewsync' "$src"
miss "does not open the App Store" 'macappstore://' "$src"
# shellcheck disable=SC2016
miss "does not retry brew bundle install" 'brew bundle install --file' "$src"
miss "does not call mas account" 'mas account' "$src"
miss "does not ask for App Store sign-in" 'App Store sign-in' "$src"

printf 'install-bundle tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
