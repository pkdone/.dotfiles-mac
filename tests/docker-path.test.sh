#!/usr/bin/env bash
# SC2016: fixtures and needles are fish source, kept literal.
# SC2317: the section's helpers are stubs called by the sourced checks/shell.sh.
# shellcheck disable=SC2016,SC2317
#
# Docker Desktop's CLI tools in fish. fish/config.fish keeps Docker Desktop's
# own PATH block at the top, with the comment markers its shellspath manager
# looks for, so a later rewrite is a no-op and the repo stays clean. The export
# appends ~/.docker/bin (Docker writes a fixed home path). The Login shell
# check treats a missing block as drift. HOME is a temp folder, and brew /
# dscl are shell functions, so nothing on this machine is read.
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
has "config.fish starts with Docker Desktop's start comment" \
  '# The following lines were added by Docker Desktop to add commands to your PATH.' "$config"
has "config.fish has Docker Desktop's end comment" \
  '# End of Docker Desktop section.' "$config"
has "config.fish uses Docker's fixed home-path export" \
  'export PATH="$PATH:/Users/paul.done/.docker/bin"' "$config"
miss "config.fish no longer adds ~/.docker/bin itself" \
  'fish_add_path --append --path $HOME/.docker/bin' "$config"
first="$(head -n 1 "$CONFIG")"
eq "the Docker start comment is line 1" \
  '# The following lines were added by Docker Desktop to add commands to your PATH.' "$first"
# One blank line between the end comment and the Homebrew heading, matching
# the spacing Docker writes: end comment, blank line, then the rest of the file.
end_line="$(grep -n -F '# End of Docker Desktop section.' "$CONFIG" | head -n 1 | cut -d: -f1)"
heading_line="$(grep -n -F '# Homebrew' "$CONFIG" | head -n 1 | cut -d: -f1)"
if [ -n "$end_line" ] && [ -n "$heading_line" ] && [ "$heading_line" -eq $((end_line + 2)) ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1)); printf 'FAIL: Homebrew heading should be one blank line after the Docker end comment (end %s, heading %s)\n' "$end_line" "$heading_line"
fi

# ---- docker_path_block / docker_path_markers --------------------------------
export MACCONFIG_CHECKS_DEFINE_ONLY=1
# shellcheck source=../checks/shell.sh disable=SC1091
. "$DIR/checks/shell.sh"
unset MACCONFIG_CHECKS_DEFINE_ONLY

eq "the repo config.fish block is found on line 1" 1 "$(docker_path_block "$CONFIG")"
eq "the repo config.fish has both Docker markers on line 1" 1 "$(docker_path_markers "$CONFIG")"
printf '%s\n%s\n' "$docker_block" "# Homebrew" > "$tmp/top.fish"
eq "a block at the top is found on line 1" 1 "$(docker_path_block "$tmp/top.fish")"
eq "a block at the top has markers on line 1" 1 "$(docker_path_markers "$tmp/top.fish")"
printf '# Homebrew\neval "$(/opt/homebrew/bin/brew shellenv)"\n%s\n' "$docker_block" > "$tmp/later.fish"
eq "a block further down is found on its first line" 3 "$(docker_path_block "$tmp/later.fish")"
eq "a block further down has markers on its first line" 3 "$(docker_path_markers "$tmp/later.fish")"
printf 'set -g x 1\nexport PATH="$PATH:$HOME/.docker/bin"\n' > "$tmp/export-only.fish"
eq "an export of ~/.docker/bin without the comment is found" 2 "$(docker_path_block "$tmp/export-only.fish")"
eq "an export without both markers is not complete" "" "$(docker_path_markers "$tmp/export-only.fish")"
printf '# The following lines were added by Docker Desktop to add commands to your PATH.\nexport PATH="$PATH:$HOME/.docker/bin"\n' > "$tmp/start-only.fish"
eq "a start comment without the end comment is not complete" "" "$(docker_path_markers "$tmp/start-only.fish")"
printf '# End of Docker Desktop section.\n' > "$tmp/end-only.fish"
eq "an end comment without the start comment is not complete" "" "$(docker_path_markers "$tmp/end-only.fish")"
eq "a missing file prints nothing for docker_path_block" "" "$(docker_path_block "$tmp/no-such.fish")"
eq "a missing file prints nothing for docker_path_markers" "" "$(docker_path_markers "$tmp/no-such.fish")"

# ---- the Login shell section ------------------------------------------------
# run_shell_section HOME — run checks/shell.sh with brew and dscl answering
# that fish is already the login shell. Same shell options as
# macconfig-check.sh, so a failing command in the section stops it here too.
run_shell_section() (
  set -euo pipefail
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
  # The Login shell section also checks ~/.local/bin/origin. Plant an
  # executable so this fixture stays about Docker's PATH block.
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/sh\nexit 0\n' > "$HOME/.local/bin/origin"
  chmod +x "$HOME/.local/bin/origin"
  # shellcheck source=../checks/shell.sh disable=SC1091
  . "$DIR/checks/shell.sh"
  printf 'checked %s\n' "$CHECKED"
)

home="$tmp/home"
mkdir -p "$home/.config/fish"
ln -s "$CONFIG" "$home/.config/fish/config.fish"
out="$(run_shell_section "$home")"
has "linked repo config.fish passes" \
  "ok fish/config.fish has Docker Desktop's PATH block (Docker's rewrite is a no-op)" "$out"
miss "linked repo config.fish is not drift" "DRIFT" "$out"
miss "linked repo config.fish does not warn" "warn " "$out"
has "login shell, Docker, and origin all count" "checked 3" "$out"

rm "$home/.config/fish/config.fish"
# A config.fish with no Docker markers is drift.
printf '# Homebrew\neval "$(/opt/homebrew/bin/brew shellenv)"\n' > "$home/.config/fish/config.fish"
out="$(run_shell_section "$home")"
has "a missing Docker block is drift" \
  "DRIFT fish/config.fish is missing Docker Desktop's PATH block" "$out"
has "the drift is tagged docker-path-block" "fixid docker-path-block" "$out"
eq "docker-path-block is report only" \
  "docker-path-block|PAUL|" "$(grep '^docker-path-block|' "$DIR/lib/autofix.list" | cut -d'|' -f1-3)"

rm "$home/.config/fish/config.fish"
out="$(run_shell_section "$home")"
miss "no config.fish, no Docker line" "Docker" "$out"
has "no config.fish still checks the login shell and origin" "checked 2" "$out"

# ---- fish accepts Docker's export and appends ~/.docker/bin -----------------
if FISH_BIN="$(hermetic_fish)"; then
  line='export PATH="$PATH:$HOME/.docker/bin"'
  fhome="$tmp/fish-home"
  mkdir -p "$fhome/xdg"
  fish_path() {
    HOME="$fhome" XDG_CONFIG_HOME="$fhome/xdg" XDG_DATA_HOME="$fhome/xdg" \
      PATH="/opt/homebrew/bin:/usr/bin:/bin" \
      "$FISH_BIN" --no-config -c "$line; string join : \$PATH"
  }
  eq "a missing ~/.docker/bin still appends the path (harmless)" \
    "/opt/homebrew/bin:/usr/bin:/bin:$fhome/.docker/bin" "$(fish_path)"
  mkdir -p "$fhome/.docker/bin"
  eq "the Docker bin folder goes after Homebrew and the system folders" \
    "/opt/homebrew/bin:/usr/bin:/bin:$fhome/.docker/bin" "$(fish_path)"
else
  printf 'docker-path tests: fish not found, PATH order checks skipped\n'
fi

printf 'docker-path tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
