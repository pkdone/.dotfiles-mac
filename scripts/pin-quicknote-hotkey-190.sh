#!/usr/bin/env bash
# Disable symbolic hotkey 190 ("Quick Note" = Globe/Fn+Q). Used by macos.sh and
# a LaunchAgent (OS updates often reset AppleSymbolicHotKeys and restore the
# Fn+Q default). Writes only when the hotkey differs: a LaunchAgent WatchPaths
# on com.apple.symbolichotkeys.plist would otherwise retrigger forever.
set -euo pipefail

LABEL='Quick Note hotkey 190'
# enabled=0, unbound parameters — same shape System Settings writes when unchecked.
DESIRED='{enabled = 0; value = { parameters = (65535, 65535, 0); type = standard; }; }'
ACTIVATE=/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings
LOG="${HOME}/Library/Logs/com.pdone.pin-quicknote-hotkey-190.log"

read_state() {
  local hk blk
  hk="$(defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null || true)"
  blk="$(printf '%s\n' "$hk" | awk '
    $0 ~ /^[[:space:]]*190 =/ {grab=1}
    grab {print}
    grab && $0 ~ /^[[:space:]]*};[[:space:]]*$/ {exit}
  ')"
  ENABLED="$(printf '%s\n' "$blk" | awk '/enabled/ {print $3; exit}' | tr -d ';' )"
  PTYPE="$(printf '%s\n' "$blk" | awk '/type/ {print $3; exit}' | tr -d '";' )"
  P1="$(printf '%s\n' "$blk" | awk '/parameters/ {getline; print $1; exit}' | tr -d ',' )"
}

log() {
  mkdir -p "$(dirname "$LOG")"
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"
}

ok_state() {
  # Accept enabled=0 or enabled=false (defaults print both forms).
  case "${ENABLED:-}" in 0|false|False) ;; *) return 1 ;; esac
  [ "${PTYPE:-}" = standard ] || return 1
  [ "${P1:-}" = 65535 ] || return 1
  return 0
}

case "${1:-}" in
  -h|--help)
    cat <<'USAGE'
Usage: pin-quicknote-hotkey-190.sh [--check]

  (default)  If Quick Note (Globe/Fn+Q) is enabled, disable hotkey 190 and activateSettings.
             If it is already disabled, do not write (safe under launchd WatchPaths).
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
    echo "$LABEL drift enabled=${ENABLED:-missing} type=${PTYPE:-?} p1=${P1:-?}"
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
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 190 "$DESIRED"
defaults read com.apple.symbolichotkeys >/dev/null 2>&1 || true
if [ -x "$ACTIVATE" ]; then
  "$ACTIVATE" -u 2>/dev/null || true
fi
msg="$LABEL pinned disabled (was enabled=${ENABLED:-missing} type=${PTYPE:-?} p1=${P1:-?})"
log "$msg"
echo "$msg"
