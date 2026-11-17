# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.

# docker_path_block FILE — line number of the first line of Docker Desktop's
# own PATH block in FILE (its "were added by Docker Desktop" comment or its
# export of ~/.docker/bin). Prints nothing when the block is not there.
# Always exits 0: macconfig-check.sh runs under set -euo pipefail.
docker_path_block() {
  [ -r "$1" ] || return 0
  awk '/^[[:space:]]*(# The following lines were added by Docker Desktop|export PATH=.*\/\.docker\/bin)/ { print NR; exit }' "$1"
}

# docker_path_markers FILE — line number of the start comment when FILE also
# has Docker Desktop's end comment. Prints nothing unless both markers are
# present. Always exits 0: macconfig-check.sh runs under set -euo pipefail.
# Those two comments are what Docker Desktop's shellspath manager looks for
# before it prepends a fresh copy of the block.
docker_path_markers() {
  [ -r "$1" ] || return 0
  awk '
    /^[[:space:]]*# The following lines were added by Docker Desktop/ && start == 0 { start = NR }
    /^[[:space:]]*# End of Docker Desktop section\./ { end = 1 }
    END { if (start && end) print start }
  ' "$1"
}

if [ "${MACCONFIG_CHECKS_DEFINE_ONLY:-}" = 1 ]; then
  return 0
fi

# ---- 5. login shell -----------------------------------------------------
hdr "Login shell"
fixid login-shell
CHECKED=$((CHECKED + 1))
FISH="$(brew --prefix 2>/dev/null)/bin/fish"
cur_shell="$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')"
if [ "$cur_shell" = "$FISH" ]; then
  pass "login shell = $cur_shell"
else
  bad "login shell = ${cur_shell:-unknown} (expected $FISH)"
fi

# fish/config.fish keeps Docker Desktop's own PATH block at the top, with the
# "added by Docker Desktop" and "End of Docker Desktop section" comments
# Docker's shellspath manager looks for. If those markers are missing, Docker
# prepends a fresh copy (and a fixed home path) and leaves the repo dirty.
fish_config="$HOME/.config/fish/config.fish"
if [ -f "$fish_config" ]; then
  fixid docker-path-block
  CHECKED=$((CHECKED + 1))
  docker_line="$(docker_path_markers "$fish_config")"
  if [ -n "$docker_line" ]; then
    pass "fish/config.fish has Docker Desktop's PATH block (Docker's rewrite is a no-op)"
  else
    bad "fish/config.fish is missing Docker Desktop's PATH block — keep the 'added by Docker Desktop' section at the top so Docker's rewrite does not dirty the repo"
  fi
fi

# gitconfig calls this path. fish/config.fish adds ~/.local/bin to PATH.
# Homebrew has no origin formula. install.sh and macconfig --fix run Cursor's
# installer only when the file is missing or not executable (lib/safe-fixers.sh).
# A directory is not a binary: -x is true for a searchable directory.
fixid origin
CHECKED=$((CHECKED + 1))
origin_bin="${ORIGIN_BIN:-$HOME/.local/bin/origin}"
if [ -f "$origin_bin" ] && [ -x "$origin_bin" ]; then
  pass "origin installed at $origin_bin"
else
  warn "origin missing or not executable at $origin_bin — run install.sh, or macconfig --fix (Cursor installer, no sudo)"
fi
