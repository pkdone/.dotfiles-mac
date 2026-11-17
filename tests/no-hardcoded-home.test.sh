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

# Home paths are built from two pieces so this file does not contain the
# strings it forbids. One exception is required: Docker Desktop writes a
# fixed home path into its PATH block in fish/config.fish, and the repo
# keeps that exact export so a rewrite is a no-op. Tests and docs may quote
# the same line.
user_old=pdone
user_now=paul.done
prefix="/Users/"
needle_old="${prefix}${user_old}"
needle_now="${prefix}${user_now}"
hits_old="$(git grep -n -F -I "$needle_old" -- . || true)"
eq "no tracked file contains the old personal home path" "" "$hits_old"

# shellcheck disable=SC2016  # the allowed export is assembled at runtime
allowed="$(printf 'export PATH="$PATH:%s/.docker/bin"' "${prefix}${user_now}")"
hits_now="$(git grep -n -F -I "$needle_now" -- . || true)"
unexpected=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in
    *"$allowed"*) ;;
    *)
      unexpected="${unexpected}${unexpected:+
}${line}"
      ;;
  esac
done <<EOF
$hits_now
EOF
eq "the only personal home-path hits are Docker Desktop's PATH export (or quotes of it)" "" "$unexpected"
has "fish/config.fish keeps Docker Desktop's fixed home-path export"   "fish/config.fish:" "$hits_now"

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
