#!/usr/bin/env bash
# Keep the Services shortcuts in lib/services-off.list off.
# Merges each drifted key into pbs NSServicesStatus with -dict-add, so every
# other service stays. Writes only when a listed key differs, then runs
# pbs -flush once. There is no LaunchAgent: this is not the symbolichotkeys
# map a software update rewrites.
# 0 and false are the same (defaults prints both).
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="${DOTFILES_SERVICES_OFF_LIST:-$DOTDIR/lib/services-off.list}"
LABEL='Services shortcuts'
DESIRED='{ enabled_context_menu = 0; enabled_services_menu = 0; presentation_modes = { ContextMenu = 0; ServicesMenu = 0; }; }'
PBS="${DOTFILES_PBS:-/System/Library/CoreServices/pbs}"
LOG="${HOME}/Library/Logs/com.pdone.pin-services-off.log"
STATUS=""
DRIFT=""

log() {
  mkdir -p "$(dirname "$LOG")"
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"
}

list_keys() {
  local line key
  [ -r "$LIST" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    key="${line#"${line%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    case "$key" in
      ''|\#*) continue ;;
    esac
    key="${key%%#*}"
    key="${key%"${key##*[![:space:]]}"}"
    [ -n "$key" ] || continue
    printf '%s\n' "$key"
  done < "$LIST"
}

read_status() {
  STATUS="$(defaults read pbs NSServicesStatus 2>/dev/null || true)"
}

# The "key" = { ... }; block, including a nested presentation_modes dict.
service_block() { # key
  awk -v key="$1" '
    function ltrim(s) { sub(/^[[:space:]]+/, "", s); return s }
    BEGIN { depth = 0; grab = 0 }
    {
      if (!grab) {
        t = ltrim($0)
        if (substr(t, 1, 1) == "\"") {
          rest = substr(t, 2)
          q = index(rest, "\"")
          if (q < 1) next
          got = substr(rest, 1, q - 1)
          after = ltrim(substr(rest, q + 1))
        } else {
          eq = index(t, " =")
          if (eq < 1) next
          got = substr(t, 1, eq - 1)
          after = ltrim(substr(t, eq + 1))
        }
        if (got != key || substr(after, 1, 1) != "=") next
        grab = 1
      }
      print
      nopen = gsub(/{/, "{")
      nclose = gsub(/}/, "}")
      depth += nopen - nclose
      if (depth <= 0) exit
    }
  ' <<<"$STATUS"
}

flag_off() {
  case "$1" in
    0|false|False) return 0 ;;
    *) return 1 ;;
  esac
}

block_field() { # block, field name
  awk -v name="$2" '
    $0 ~ ("^[[:space:]]*" name "[[:space:]]*=") {
      v = $NF
      gsub(/[;"]/, "", v)
      print v
      exit
    }
  ' <<<"$1"
}

block_off() { # block text
  local blk="$1" cm sm pcm psm
  cm="$(block_field "$blk" enabled_context_menu)"
  sm="$(block_field "$blk" enabled_services_menu)"
  pcm="$(block_field "$blk" ContextMenu)"
  psm="$(block_field "$blk" ServicesMenu)"
  flag_off "$cm" && flag_off "$sm" && flag_off "$pcm" && flag_off "$psm"
}

collect_drift() {
  local key blk
  DRIFT=""
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    blk="$(service_block "$key")"
    if block_off "$blk"; then
      continue
    fi
    DRIFT="${DRIFT}${DRIFT:+$'\n'}${key}"
  done <<EOF
$(list_keys)
EOF
}

require_list() {
  if [ -r "$LIST" ]; then
    return 0
  fi
  echo "$LABEL list missing: $LIST" >&2
  exit 1
}

case "${1:-}" in
  -h|--help)
    cat <<'USAGE'
Usage: pin-services-off.sh [--check]

  (default)  For each key in lib/services-off.list that is not off, merge that
             key into pbs NSServicesStatus and run pbs -flush once.
             A key that is already off is not written. Other services stay.
  --check    Exit 0 if every listed key is off; exit 1 and name the rest.
USAGE
    exit 0
    ;;
  --check)
    require_list
    read_status
    collect_drift
    if [ -z "$DRIFT" ]; then
      echo "$LABEL ok (off)"
      exit 0
    fi
    echo "$LABEL drift ${DRIFT//$'\n'/, }"
    exit 1
    ;;
esac

require_list
read_status
collect_drift
if [ -z "$DRIFT" ]; then
  msg="$LABEL already off (left alone)"
  log "$msg"
  echo "$msg"
  exit 0
fi

wrote=0
while IFS= read -r key; do
  [ -n "$key" ] || continue
  defaults write pbs NSServicesStatus -dict-add "$key" "$DESIRED"
  wrote=1
done <<EOF
$DRIFT
EOF
if [ "$wrote" = 1 ]; then
  defaults read pbs >/dev/null 2>&1 || true
  if [ -x "$PBS" ]; then
    "$PBS" -flush >/dev/null 2>&1 || true
  fi
fi
msg="$LABEL pinned off (${DRIFT//$'\n'/, })"
log "$msg"
echo "$msg"
