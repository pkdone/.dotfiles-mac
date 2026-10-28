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

# fish/config.fish adds ~/.docker/bin itself. Docker Desktop can still insert
# its own export block at the top of the file it finds at this path.
fish_config="$HOME/.config/fish/config.fish"
if [ -f "$fish_config" ]; then
  fixid docker-path-block
  CHECKED=$((CHECKED + 1))
  docker_line="$(docker_path_block "$fish_config")"
  if [ -n "$docker_line" ]; then
    warn "fish/config.fish line $docker_line: Docker Desktop added its own PATH block. Remove it; config.fish already adds ~/.docker/bin"
  else
    pass "fish/config.fish has no Docker Desktop PATH block"
  fi
fi
