#!/usr/bin/env bash
# Disable symbolic hotkey 260 ("Game Overlay" = Command+Escape).
# A software update rewrites AppleSymbolicHotKeys and turns this shortcut
# back on, so macos.sh and a LaunchAgent both call this script. Writes only
# when the hotkey differs: a LaunchAgent WatchPaths on
# com.apple.symbolichotkeys.plist would otherwise retrigger forever.
# enabled=0 and enabled=false are the same (defaults prints both).
set -euo pipefail

LABEL='Game Overlay hotkey 260'
# Same shape System Settings writes when the Mission Control box is unticked:
# the Command+Escape combo stays (keycode 53, command flag 1048576) and the
# character slot is the unbound sentinel 65535.
DESIRED='{enabled = 0; value = { parameters = (65535, 53, 1048576); type = standard; }; }'
ACTIVATE="${DOTFILES_ACTIVATE_SETTINGS:-/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings}"
LOG="${HOME}/Library/Logs/com.pdone.pin-gameoverlay-hotkey-260.log"

read_state() {
  local hk blk
  hk="$(defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null || true)"
  # awk exits as soon as the block ends. A pipe would then raise SIGPIPE in
  # the writer, and pipefail would abort a hotkey that was already correct.
  # A here-string is a file, so the early exit is harmless.
  blk="$(awk '
    $0 ~ /^[[:space:]]*260 =/ {grab=1}
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
  case "${ENABLED:-}" in 0|false|False) ;; *) return 1 ;; esac
  [ "${PTYPE:-}" = standard ] || return 1
  [ "${P1:-}" = 65535 ] || return 1
  [ "${P2:-}" = 53 ] || return 1
  [ "${P3:-}" = 1048576 ] || return 1
  return 0
}

case "${1:-}" in
  -h|--help)
    cat <<'USAGE'
Usage: pin-gameoverlay-hotkey-260.sh [--check]

  (default)  If Game Overlay (Command+Escape) is enabled, disable hotkey 260
             and activateSettings. If it is already disabled, do not write
             (safe under launchd WatchPaths).
  --check    Exit 0 if already disabled; exit 1 and print current state otherwise.
USAGE
    exit 0
    ;;
  --check)
    read_state
    if ok_state; then
      echo "$LABEL ok (disabled)"
      exit 0
    fi
    echo "$LABEL drift enabled=${ENABLED:-missing} type=${PTYPE:-?} p1=${P1:-?} p2=${P2:-?} p3=${P3:-?}"
    exit 1
    ;;
esac

read_state
if ok_state; then
  msg="$LABEL already disabled (left alone)"
  log "$msg"
  echo "$msg"
  exit 0
fi
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 260 "$DESIRED"
defaults read com.apple.symbolichotkeys >/dev/null 2>&1 || true
if [ -x "$ACTIVATE" ]; then
  "$ACTIVATE" -u 2>/dev/null || true
fi
msg="$LABEL pinned disabled (was enabled=${ENABLED:-missing} type=${PTYPE:-?} p1=${P1:-?} p2=${P2:-?} p3=${P3:-?})"
log "$msg"
echo "$msg"
