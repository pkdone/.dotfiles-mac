#!/usr/bin/env bash
#
# No tracked file may contain a literal personal home path. gitconfig's origin
# credential helpers are `!` shell commands, so they use $HOME (git runs those
# through the shell, which expands $HOME and ~). The marker is built from two
# pieces so this test does not contain the path it forbids.
# Run: ./tests/no-hardcoded-home.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR" || exit 1

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

user=pdone
needle="$(printf '%s%s' '/Users/' "$user")"
hits="$(git grep -n -F -I "$needle" -- . || true)"
eq "no tracked file contains the personal home path" "" "$hits"

# shellcheck disable=SC2016  # the helper text is compared literally
helpers="$(git grep -F '!$HOME/.local/bin/origin credential-helper' -- gitconfig || true)"
eq "both origin credential helpers use \$HOME" 2 "$(printf '%s\n' "$helpers" | grep -c .)"

runner="$(cat "$DIR/tests/run-all.sh")"
has "mac-home copies under a .dotfiles-mac-style path" '/.dotfiles-mac-style' "$runner"
# shellcheck disable=SC2016  # needles are source text, compared literally
has "mac-home path is under /Users" 'parent="/Users/${MAC_NAME}"' "$runner"
has "default mac-home account is the one that failed locally" 'MAC_NAME="pdone"' "$runner"
# shellcheck disable=SC2016  # needle is source text, compared literally
has "mac-home sets HOME" 'HOME="$parent"' "$runner"

printf 'no-hardcoded-home tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
