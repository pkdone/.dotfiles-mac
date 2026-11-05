# shellcheck shell=bash
#
# safe-fixers.sh — the SAFE fixers bootstrap and `macconfig-check.sh --fix` share.
# Sourced, not executed. One implementation of each setter, so a fresh Mac
# (install.sh / dock.sh) and a later --fix cannot drift.
#
#   safe_start_hammerspoon   open -g -a Hammerspoon, only if installed and not running
#   safe_apply_desktops      lib/desktop-bindings.py --apply (backup, app-bindings,
#                            restart Dock only if a pin changed)
#   safe_install_origin      Cursor's origin installer, only when
#                            $HOME/.local/bin/origin is missing or not an
#                            executable file. No sudo, no version pin.
#                            Copies the repo gitconfig and writes it back
#                            if that run changes it. Only that file.
#
# DRY_RUN=1 prints what would happen and changes nothing. No sudo.

SAFE_FIXERS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Start Hammerspoon when the app is installed and the process is not already
# running. Prints one line. Returns 0 (started, already running, or dry-run),
# 1 (open did not start it), or 2 (not installed).
#
# SAFE_HAMMERSPOON_DESCRIBE=1 is install.sh --dry-run: the Brewfile cask would
# be installed first, so a missing app still gets the would-start line.
# HAMMERSPOON_APP overrides the install check (tests). The open command stays
# `open -g -a Hammerspoon`, the same one macconfig --fix has always used.
safe_start_hammerspoon() {
  local app i=0
  app="${HAMMERSPOON_APP:-/Applications/Hammerspoon.app}"
  if [ ! -d "$app" ]; then
    if [ "${SAFE_HAMMERSPOON_DESCRIBE:-0}" = 1 ]; then
      echo "would start Hammerspoon (open -g -a Hammerspoon) if it is installed and not running"
      return 0
    fi
    echo "Hammerspoon.app not installed — run brewsync"
    return 2
  fi
  if pgrep -xq Hammerspoon; then
    echo "Hammerspoon already running"
    return 0
  fi
  if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "would start Hammerspoon (open -g -a Hammerspoon)"
    return 0
  fi
  open -g -a Hammerspoon 2>/dev/null || true
  while [ "$i" -lt 15 ] && ! pgrep -xq Hammerspoon; do
    sleep 1
    i=$((i + 1))
  done
  if pgrep -xq Hammerspoon; then
    echo "started Hammerspoon"
    return 0
  fi
  echo "open -a Hammerspoon didn't start it"
  return 1
}

# Install the Cursor origin CLI when the binary is missing or not executable.
# Homebrew has no formula. The official installer writes $HOME/.local/bin/origin
# and does not use sudo. An executable file is left alone, so a later run does
# not download and does not pin a version.
#
# The published installer (https://downloads.cursor.com/origin/install.sh) has
# no option to skip git config. Its variables are ORIGIN_INSTALL_CHANNEL,
# ORIGIN_INSTALL_DIR, ORIGIN_BIN_DIR, XDG_CONFIG_HOME, and the legacy CO_*
# names for the first three. On Paul's Mac the installer rewrote ~/.gitconfig:
# both origin credential helpers became an absolute home path, and the blank
# helper lines moved. That path is a symlink to this repo's gitconfig, so the
# tracked file changed. Copy this one file before the installer and write those
# bytes back only when they differ. Do not restore any other path.
#
# ORIGIN_BIN overrides the path (tests). ORIGIN_INSTALL_URL overrides the
# installer URL. ORIGIN_GITCONFIG overrides the repo gitconfig path (tests).
# Prints one line. Returns 0 (already installed, installed, or dry-run) or 1
# (the installer failed, it finished without an executable, or gitconfig could
# not be snapshotted or restored).
safe_install_origin() {
  local bin url shown gitconfig snap rc
  bin="${ORIGIN_BIN:-$HOME/.local/bin/origin}"
  url="${ORIGIN_INSTALL_URL:-https://downloads.cursor.com/origin/install.sh}"
  gitconfig="${ORIGIN_GITCONFIG:-$SAFE_FIXERS_ROOT/gitconfig}"
  shown="$bin"
  case "$shown" in
    "$HOME"/*) shown="~${shown#"$HOME"}" ;;
  esac
  if [ -f "$bin" ] && [ -x "$bin" ]; then
    echo "origin already installed ($shown)"
    return 0
  fi
  if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "would install origin (curl -fsSL $url | sh) because $shown is missing or not executable"
    return 0
  fi

  # Callers run this under `||`, which turns set -e off for the whole function.
  # A failed snapshot must stop the installer: there would be nothing to put back.
  snap=""
  if [ -f "$gitconfig" ]; then
    snap="$(mktemp)" || snap=""
    if [ -z "$snap" ] || ! cat "$gitconfig" > "$snap"; then
      rm -f "$snap"
      echo "could not snapshot gitconfig ($gitconfig)"
      return 1
    fi
  fi

  rc=0
  if curl -fsSL "$url" | sh; then
    if [ -f "$bin" ] && [ -x "$bin" ]; then
      echo "installed origin ($shown)"
    else
      echo "origin installer finished but $shown is still missing or not executable"
      rc=1
    fi
  else
    echo "origin installer failed ($shown)"
    rc=1
  fi

  if [ -n "$snap" ]; then
    if [ ! -f "$gitconfig" ] || ! cmp -s "$snap" "$gitconfig"; then
      if ! cat "$snap" > "$gitconfig"; then
        echo "could not restore gitconfig ($gitconfig); snapshot left at $snap"
        return 1
      fi
    fi
    rm -f "$snap"
  fi
  return "$rc"
}

# Apply lib/desktop-bindings.list. Extra arguments go to desktop-bindings.py
# before the list path (`--dry-run`, `--only id,id`). Prints the helper's
# status|bundle|message lines. Returns its status, or 2 when python3 is missing
# (one fail line per --only id, or a single fail line when applying the list).
safe_apply_desktops() {
  local py only="" arg prev=""
  for arg in "$@"; do
    if [ "$prev" = "--only" ]; then
      only="$arg"
    fi
    prev="$arg"
  done
  # shellcheck source=defaults-lib.sh disable=SC1091
  . "$SAFE_FIXERS_ROOT/lib/defaults-lib.sh"
  if ! py="$(dot_python)"; then
    if [ -n "$only" ]; then
      while IFS= read -r arg; do
        [ -n "$arg" ] || continue
        printf 'fail|%s|python3 not found — desktop assignment not changed\n' "$arg"
      done < <(printf '%s\n' "$only" | tr ',' '\n')
    else
      printf 'fail||python3 not found — desktop assignment not changed\n'
    fi
    return 2
  fi
  "$py" "$SAFE_FIXERS_ROOT/lib/desktop-bindings.py" --apply "$@" "$SAFE_FIXERS_ROOT/lib/desktop-bindings.list"
}
