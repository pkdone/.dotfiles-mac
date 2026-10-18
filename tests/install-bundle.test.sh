#!/usr/bin/env bash
#
# install.sh's Brewfile retry: a failed `brew bundle check` on a terminal opens
# the App Store, asks for a sign-in, and retries `brew bundle install` once.
# Non-interactive runs keep the warning. This does not execute install.sh
# (it refuses to run off Darwin) and it does not call `mas`.
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
has "TTY guard is stdin" '[ -t 0 ]' "$src"
has "opens the App Store URL" "open 'macappstore://'" "$src"
# shellcheck disable=SC2016
has "retries brew bundle install once" 'brew bundle install --file "$DOTFILES/Brewfile"' "$src"
has "keeps the non-interactive warning" 'some Brewfile entries did not install' "$src"
miss "does not call mas account" 'mas account' "$src"

# The retry sits in the TTY branch, after the check, and runs once.
order="$(awk '
  /brew bundle check --file/ && !seen_check++ { print NR " check" }
  /\[ -t 0 \]/ { print NR " tty" }
  /macappstore:\/\// { print NR " open" }
  /brew bundle install --file/ { print NR " retry" }
' "$INSTALL")"
check_n="$(printf '%s\n' "$order" | awk '$2 == "check" { print $1; exit }')"
tty_n="$(printf '%s\n' "$order" | awk '$2 == "tty" { print $1; exit }')"
open_n="$(printf '%s\n' "$order" | awk '$2 == "open" { print $1; exit }')"
retry_n="$(printf '%s\n' "$order" | awk '$2 == "retry" { print $1; exit }')"
# Count retries: the first `brew bundle` is not `brew bundle install`.
retry_count="$(grep -c 'brew bundle install --file' "$INSTALL" || true)"
eq "brew bundle install is retried once" 1 "$retry_count"
if [ -n "$check_n" ] && [ -n "$tty_n" ] && [ -n "$open_n" ] && [ -n "$retry_n" ] \
  && [ "$check_n" -lt "$tty_n" ] && [ "$tty_n" -lt "$open_n" ] && [ "$open_n" -lt "$retry_n" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL: retry order\n  %s\n' "$order"
fi

printf 'install-bundle tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
