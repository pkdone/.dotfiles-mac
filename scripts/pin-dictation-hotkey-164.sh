#!/usr/bin/env bash
# Pin symbolic hotkey 164 ("Start Dictation") to Right Command twice so hold-Fn
# never owns the mic. Idempotent. Used by macos.sh and a login LaunchAgent
# (OS updates often reset AppleSymbolicHotKeys to the unbound default).
set -euo pipefail

LABEL='dictation hotkey 164'
DESIRED='{enabled = 1; value = { parameters = (1048592, 54, 0); type = modifier; }; }'
ACTIVATE=/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings
LOG="${HOME}/Library/Logs/com.pdone.pin-dictation-hotkey-164.log"

read_state() {
  local hk blk
  hk="$(defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null || true)"
  blk="$(printf '%s\n' "$hk" | awk '
    $0 ~ /^[[:space:]]*164 =/ {grab=1}
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

case "${1:-}" in
  -h|--help)
    cat <<'USAGE'
Usage: pin-dictation-hotkey-164.sh [--check]

  (default)  Write Right Command twice for hotkey 164 and activateSettings.
  --check    Exit 0 if already correct; exit 1 and print current state otherwise.
USAGE
    exit 0
    ;;
  --check)
    read_state
    if [ "${ENABLED:-}" = 1 ] && [ "${PTYPE:-}" = modifier ] && [ "${P1:-}" = 1048592 ]; then
      echo "$LABEL ok (Right Command twice)"
      exit 0
    fi
    echo "$LABEL drift enabled=${ENABLED:-?} type=${PTYPE:-?} p1=${P1:-?}"
    exit 1
    ;;
esac

read_state
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 164 "$DESIRED"
defaults read com.apple.symbolichotkeys >/dev/null 2>&1 || true
if [ -x "$ACTIVATE" ]; then
  "$ACTIVATE" -u 2>/dev/null || true
fi
if [ "${ENABLED:-}" = 1 ] && [ "${PTYPE:-}" = modifier ] && [ "${P1:-}" = 1048592 ]; then
  msg="$LABEL re-asserted (already Right Command twice)"
else
  msg="$LABEL pinned (was enabled=${ENABLED:-?} type=${PTYPE:-?} p1=${P1:-?})"
fi
log "$msg"
echo "$msg"
