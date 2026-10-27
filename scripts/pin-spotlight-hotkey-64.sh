#!/usr/bin/env bash
# Restore symbolic hotkey 64 ("Show Spotlight search") to Command+Space.
# Raycast's Replace Spotlight button sets enabled=0. Used by macos.sh and
# macconfig --fix. Writes only when the hotkey differs. There is no
# LaunchAgent for this key.
set -euo pipefail

LABEL='Spotlight hotkey 64'
DESIRED='{enabled = 1; value = { parameters = (32, 49, 1048576); type = standard; }; }'
ACTIVATE="${DOTFILES_ACTIVATE_SETTINGS:-/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings}"
LOG="${HOME}/Library/Logs/com.pdone.pin-spotlight-hotkey-64.log"

read_state() {
  local hk blk
  hk="$(defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null || true)"
  # awk exits as soon as the block ends. A pipe would then raise SIGPIPE in
  # the writer, and pipefail would abort a hotkey that was already correct.
  # A here-string is a file, so the early exit is harmless.
  blk="$(awk '
    $0 ~ /^[[:space:]]*64 =/ {grab=1}
    grab {print}
    grab && $0 ~ /^[[:space:]]*};[[:space:]]*$/ {exit}
  ' <<<"$hk")"
  ENABLED="$(awk '/enabled/ {print $3; exit}' <<<"$blk" | tr -d ';')"
  PTYPE="$(awk '/type/ {print $3; exit}' <<<"$blk" | tr -d '";')"
  P1="$(awk '/parameters/ {getline; print $1; exit}' <<<"$blk" | tr -d ',')"
  P2="$(awk '/parameters/ {getline; getline; print $1; exit}' <<<"$blk" | tr -d ',')"
  P3="$(awk '/parameters/ {getline; getline; getline; print $1; exit}' <<<"$blk" | tr -d ',')"
}

log() {
  mkdir -p "$(dirname "$LOG")"
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"
}

ok_state() {
  [ "${ENABLED:-}" = 1 ] && [ "${PTYPE:-}" = standard ] \
    && [ "${P1:-}" = 32 ] && [ "${P2:-}" = 49 ] && [ "${P3:-}" = 1048576 ]
}

case "${1:-}" in
  -h|--help)
    cat <<'USAGE'
Usage: pin-spotlight-hotkey-64.sh [--check]

  (default)  If hotkey 64 is not Command+Space, write it and activateSettings.
             If it already matches, do not write.
  --check    Exit 0 if already correct; exit 1 and print current state otherwise.
USAGE
    exit 0
    ;;
  --check)
    read_state
    if ok_state; then
      echo "$LABEL ok (Command+Space)"
      exit 0
    fi
    echo "$LABEL drift enabled=${ENABLED:-missing} type=${PTYPE:-?} p1=${P1:-?} p2=${P2:-?} p3=${P3:-?}"
    exit 1
    ;;
esac

read_state
if ok_state; then
  msg="$LABEL already Command+Space (left alone)"
  log "$msg"
  echo "$msg"
  exit 0
fi
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 "$DESIRED"
defaults read com.apple.symbolichotkeys >/dev/null 2>&1 || true
if [ -x "$ACTIVATE" ]; then
  "$ACTIVATE" -u 2>/dev/null || true
fi
msg="$LABEL pinned (was enabled=${ENABLED:-missing} type=${PTYPE:-?} p1=${P1:-?} p2=${P2:-?} p3=${P3:-?})"
log "$msg"
echo "$msg"
