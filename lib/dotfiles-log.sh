# shellcheck shell=bash
#
# dotfiles-log.sh — one log per run of install.sh, bootstrap.sh, and brewsync.
# Sourced, not executed.
#
# Logs are only created under ~/Library/Logs/dotfiles/. The directory is
# refused when it would land inside this repo, so a tee can never write the
# checkout. The wrapper copies the script's own stdout and stderr. It does
# not print the environment, and sudo reads the admin password from the
# terminal, so secrets are not written to the log.

# dotfiles_refuse_root CMD — exit if this process is root.
dotfiles_refuse_root() {
  if [ "$(id -u)" -eq 0 ]; then
    echo "$1: refusing to run as root. Run it as your user account. It will ask for an admin password if an installer needs one." >&2
    exit 1
  fi
}

# True when the original terminal was interactive. The log wrapper pipes
# stdout through tee, so the inner script's stdout is not a tty; the wrapper
# records the outer terminal in DOTFILES_INTERACTIVE before that redirect.
dotfiles_is_interactive() {
  case "${DOTFILES_INTERACTIVE:-}" in
    1) return 0 ;;
    0) return 1 ;;
  esac
  [ -t 0 ] && [ -t 1 ]
}

# Resolve a directory that may not exist yet, so the repo check can run
# before mkdir. Walk up to the nearest existing parent and append the rest.
dotfiles_resolve_dir() {
  local path="$1" existing rest base
  existing="$path"
  rest=""
  while [ ! -d "$existing" ]; do
    base="$(basename "$existing")"
    existing="$(dirname "$existing")"
    rest="/${base}${rest}"
    if [ "$existing" = "/" ]; then
      break
    fi
  done
  if [ -d "$existing" ]; then
    existing="$(cd "$existing" && pwd -P)" || return 1
  fi
  printf '%s\n' "${existing}${rest}"
}

# Print the path of a new log for NAME and delete logs older than 30 days.
# NAME is the script (install, bootstrap, brewsync). Nothing is created when
# the log directory would be inside the repo.
dotfiles_new_log() {
  local name="$1" dir resolved repo lib_dir
  case "$name" in
    ''|*[!A-Za-z0-9._-]*)
      echo "Internal error: refusing log name '$name'." >&2
      return 1
      ;;
  esac
  dir="$HOME/Library/Logs/dotfiles"
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || return 1
  repo="$(cd "$lib_dir/.." && pwd -P)" || return 1
  resolved="$(dotfiles_resolve_dir "$dir")" || return 1
  case "$resolved/" in
    "$repo/"*)
      echo "Refusing to write logs inside the repo checkout ($resolved)." >&2
      echo "Logs belong in ~/Library/Logs/dotfiles/." >&2
      return 1
      ;;
  esac
  mkdir -p "$dir" || return 1
  # -maxdepth 1 so a stray symlink cannot make find walk into the repo.
  find "$dir" -maxdepth 1 -type f -name '*.log' -mtime +30 -delete 2>/dev/null || true
  printf '%s\n' "$dir/${name}-$(date +%Y%m%d-%H%M%S).log"
}

# Re-exec the caller once with stdout and stderr appended to a dated log.
# The outer process prints the log path and exits with the inner status.
# A second entry (the re-exec) returns immediately.
dotfiles_log_exec() {
  local name="$1"
  shift
  if [ "${DOTFILES_LOG_WRAPPED:-}" = "$name" ]; then
    return 0
  fi
  local caller script log rc
  caller="${BASH_SOURCE[1]}"
  script="$(cd "$(dirname "$caller")" && pwd)/$(basename "$caller")"
  if ! log="$(dotfiles_new_log "$name")"; then
    exit 1
  fi
  # bootstrap.sh logs, then runs install.sh, which logs again. The inner
  # script's stdout is the outer tee, so it is not a tty. The outer run
  # already recorded the real terminal. Do not clear that, or a pkg cask
  # never gets the one sudo -v prompt.
  if [ -z "${DOTFILES_INTERACTIVE+x}" ]; then
    if [ -t 0 ] && [ -t 1 ]; then
      export DOTFILES_INTERACTIVE=1
    else
      export DOTFILES_INTERACTIVE=0
    fi
  fi
  if [ -z "${DOTFILES_STDOUT_TTY+x}" ]; then
    if [ -t 1 ]; then
      export DOTFILES_STDOUT_TTY=1
    else
      export DOTFILES_STDOUT_TTY=0
    fi
  fi
  export DOTFILES_LOG_WRAPPED="$name"
  export DOTFILES_LOG_FILE="$log"
  set +e
  set +o pipefail
  "$script" "$@" 2>&1 | tee -a "$log"
  rc=${PIPESTATUS[0]}
  set -o pipefail
  set -e
  set +e
  printf 'Log: %s\n' "$log" | tee -a "$log"
  exit "$rc"
}

# dotfiles_note_logout ITEM — remember one setting that still needs a logout.
# bootstrap.sh prints the list at the end of a guided run. A macos.sh run on
# its own leaves DOTFILES_LOGOUT_FILE unset, so this does nothing and macos.sh
# still prints its own note.
dotfiles_note_logout() {
  local item="$1" file
  [ -n "$item" ] || return 0
  file="${DOTFILES_LOGOUT_FILE:-}"
  [ -n "$file" ] || return 0
  printf '%s\n' "$item" >>"$file" || true
}

# Print the queued logout items, one per line, in the order they were noted,
# dropping a later duplicate. Prints nothing when the queue is empty.
dotfiles_logout_items() {
  local file="${DOTFILES_LOGOUT_FILE:-}"
  [ -n "$file" ] && [ -f "$file" ] || return 0
  awk 'NF && !seen[$0]++' "$file"
}

# Prominent notice for the end of bootstrap.sh. $1 and $2 are optional colour
# on and off sequences for the heading. Prints nothing when nothing is queued.
dotfiles_print_logout_notice() {
  local items item hdr="${1:-}" off="${2:-}"
  items="$(dotfiles_logout_items)" || return 0
  [ -n "$items" ] || return 0
  printf '\n%sLog out and back in now to finish applying:%s\n' "$hdr" "$off"
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    printf '  - %s\n' "$item"
  done <<< "$items"
}
