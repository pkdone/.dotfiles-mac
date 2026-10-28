#!/usr/bin/env bash
# SC2016: fixtures and needles are fish source, kept literal.
# SC2317: the section's helpers are stubs called by the sourced checks/shell.sh.
# shellcheck disable=SC2016,SC2317
#
# Docker Desktop's CLI tools in fish. fish/config.fish appends ~/.docker/bin
# to PATH, after Homebrew, only when that folder exists, with no fixed home
# path. The Login shell check warns when Docker Desktop's own "added by Docker
# Desktop" export block is back in config.fish. HOME is a temp folder, and
# brew / dscl are shell functions, so nothing on this machine is read.
# Run: ./tests/docker-path.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hermetic.sh disable=SC1091
. "$DIR/tests/hermetic.sh"
CONFIG="$DIR/fish/config.fish"

pass=0
fail=0
eq() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
has() {
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;; esac
}
miss() {
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n' "$1" "$2" ;;
    *) pass=$((pass + 1)) ;; esac
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

docker_block='# The following lines were added by Docker Desktop to add commands to your PATH.
export PATH="$PATH:/Users/someone/.docker/bin"
# End of Docker Desktop section.'

# ---- config.fish -----------------------------------------------------------
config="$(cat "$CONFIG")"
has "config.fish appends ~/.docker/bin when it exists" \
  'test -d $HOME/.docker/bin; and fish_add_path --append --path $HOME/.docker/bin' "$config"
miss "config.fish has no Docker Desktop block" "were added by Docker Desktop" "$config"
miss "config.fish has no export PATH line" "export PATH" "$config"
miss "config.fish names no home folder" "/Users/" "$config"
has "config.fish says to remove the block if it comes back" "If it adds that block again, remove it" "$config"
brew_line="$(grep -n -F 'brew shellenv' "$CONFIG" | head -n 1 | cut -d: -f1)"
docker_at="$(grep -n -F 'fish_add_path --append --path $HOME/.docker/bin' "$CONFIG" | head -n 1 | cut -d: -f1)"
if [ -n "$brew_line" ] && [ -n "$docker_at" ] && [ "$docker_at" -gt "$brew_line" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1)); printf 'FAIL: the Docker line comes after Homebrew (brew %s, docker %s)\n' "$brew_line" "$docker_at"
fi

# ---- docker_path_block ----------------------------------------------------
export MACCONFIG_CHECKS_DEFINE_ONLY=1
# shellcheck source=../checks/shell.sh disable=SC1091
. "$DIR/checks/shell.sh"
unset MACCONFIG_CHECKS_DEFINE_ONLY

eq "the repo config.fish has no Docker block" "" "$(docker_path_block "$CONFIG")"
printf '%s\n%s\n' "$docker_block" "$config" > "$tmp/top.fish"
eq "a block at the top is found on line 1" 1 "$(docker_path_block "$tmp/top.fish")"
printf '# Homebrew\neval "$(/opt/homebrew/bin/brew shellenv)"\n%s\n' "$docker_block" > "$tmp/later.fish"
eq "a block further down is found on its first line" 3 "$(docker_path_block "$tmp/later.fish")"
printf 'set -g x 1\nexport PATH="$PATH:$HOME/.docker/bin"\n' > "$tmp/export-only.fish"
eq "an export of ~/.docker/bin without the comment is found" 2 "$(docker_path_block "$tmp/export-only.fish")"
eq "a missing file prints nothing" "" "$(docker_path_block "$tmp/no-such.fish")"

# ---- the Login shell section ------------------------------------------------
# run_shell_section HOME — run checks/shell.sh with brew and dscl answering
# that fish is already the login shell.
run_shell_section() (
  HOME="$1"
  USER=tester
  CHECKED=0
  brew() { printf '/opt/homebrew\n'; }
  dscl() { printf 'UserShell: /opt/homebrew/bin/fish\n'; }
  hdr() { printf '[%s]\n' "$1"; }
  fixid() { printf 'fixid %s\n' "$1"; }
  pass() { printf 'ok %s\n' "$1"; }
  bad() { printf 'DRIFT %s\n' "$1"; }
  warn() { printf 'warn %s\n' "$1"; }
  # shellcheck source=../checks/shell.sh disable=SC1091
  . "$DIR/checks/shell.sh"
  printf 'checked %s\n' "$CHECKED"
)

home="$tmp/home"
mkdir -p "$home/.config/fish"
ln -s "$CONFIG" "$home/.config/fish/config.fish"
out="$(run_shell_section "$home")"
has "linked repo config.fish passes" "ok fish/config.fish has no Docker Desktop PATH block" "$out"
miss "linked repo config.fish does not warn" "warn " "$out"
has "both shell checks count" "checked 2" "$out"

rm "$home/.config/fish/config.fish"
cp "$tmp/top.fish" "$home/.config/fish/config.fish"
out="$(run_shell_section "$home")"
has "Docker's block is a warning that names the line" \
  "warn fish/config.fish line 1: Docker Desktop added its own PATH block. Remove it" "$out"
has "the warning is tagged docker-path-block" "fixid docker-path-block" "$out"
miss "Docker's block is not drift" "DRIFT" "$out"
eq "docker-path-block is report only" \
  "docker-path-block|PAUL|" "$(grep '^docker-path-block|' "$DIR/lib/autofix.list" | cut -d'|' -f1-3)"

rm "$home/.config/fish/config.fish"
out="$(run_shell_section "$home")"
miss "no config.fish, no Docker line" "Docker" "$out"
has "no config.fish counts only the login shell" "checked 1" "$out"

# ---- fish puts ~/.docker/bin last, and only when it exists ------------------
if FISH_BIN="$(hermetic_fish)"; then
  line="$(grep -F '.docker/bin' "$CONFIG" | grep -v '^[[:space:]]*#')"
  fhome="$tmp/fish-home"
  mkdir -p "$fhome/xdg"
  fish_path() {
    HOME="$fhome" XDG_CONFIG_HOME="$fhome/xdg" XDG_DATA_HOME="$fhome/xdg" \
      PATH="/opt/homebrew/bin:/usr/bin:/bin" \
      "$FISH_BIN" --no-config -c "$line; string join : \$PATH"
  }
  eq "no ~/.docker/bin leaves PATH alone" "/opt/homebrew/bin:/usr/bin:/bin" "$(fish_path)"
  mkdir -p "$fhome/.docker/bin"
  eq "the Docker bin folder goes after Homebrew and the system folders" \
    "/opt/homebrew/bin:/usr/bin:/bin:$fhome/.docker/bin" "$(fish_path)"
  eq "fish_add_path --path writes no universal variables" "" "$(find "$fhome/xdg" -name fish_variables)"
else
  printf 'docker-path tests: fish not found, PATH order checks skipped\n'
fi

printf 'docker-path tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
