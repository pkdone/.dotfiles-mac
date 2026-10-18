#!/usr/bin/env bash
#
# Menu bar: the three new @host/com.apple.controlcenter rows (Voice Control,
# Bluetooth, battery percentage), the ControlCenter restart those rows share
# with Spotlight / Focus / Now Playing, the Karabiner menu bar flags, and the
# third-party allow-list manual step. macos.sh is driven with a fake
# `defaults` and `killall` so this runs on Linux CI and never touches a live
# ControlCenter. Run: ./tests/menubar.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="$DIR/lib/macos-defaults.list"
MACOS="$DIR/macos.sh"
KJ="$DIR/karabiner/karabiner.json"
CHECK="$DIR/macconfig-check.sh"

pass=0
fail=0
eq() {  # description expected actual
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
has() {  # description needle haystack
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;; esac
}
miss() {  # description needle haystack
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n' "$1" "$2" ;;
    *) pass=$((pass + 1)) ;; esac
}

rows="$(grep -vE '^[[:space:]]*(#|$)' "$LIST")"
field() {  # domain key field-number (1-based)
  awk -F'|' -v d="$1" -v k="$2" -v f="$3" '$1 == d && $2 == k { print $f; exit }' "$LIST"
}

HOST='@host/com.apple.controlcenter'

# ---- list rows (the single source macos.sh and macconfig-check.sh share) ----
for row in \
  "$HOST|VoiceControl|int|8|ControlCenter|Menu Bar|Voice Control|" \
  "$HOST|Bluetooth|int|2|ControlCenter|Menu Bar|Bluetooth|" \
  "$HOST|BatteryShowPercentage|bool|true|ControlCenter|Menu Bar|Battery percentage|"
do
  has "defaults row $(printf '%s' "$row" | cut -d'|' -f2)" "$row" "$rows"
done

eq "Voice Control is int 8" 8 "$(field "$HOST" VoiceControl 4)"
eq "Voice Control type is int" int "$(field "$HOST" VoiceControl 3)"
eq "Bluetooth is int 2" 2 "$(field "$HOST" Bluetooth 4)"
eq "battery percentage is bool true" true "$(field "$HOST" BatteryShowPercentage 4)"
eq "battery percentage type is bool" bool "$(field "$HOST" BatteryShowPercentage 3)"
for key in Spotlight FocusModes NowPlaying VoiceControl Bluetooth BatteryShowPercentage; do
  eq "$key restarts ControlCenter" ControlCenter "$(field "$HOST" "$key" 5)"
done

eq "defaults fixer is still SAFE macos" "SAFE|macos" \
  "$(awk -F'|' '$1=="defaults" { print $2 "|" $3; exit }' "$DIR/lib/autofix.list")"
has "autofix comment names ControlCenter" "SystemUIServer / ControlCenter" \
  "$(cat "$DIR/lib/autofix.list")"

has "manual step hides Raycast, Logi Options+ and Docker" \
  "menubar-third-party-hide|Menu bar|Allow in the Menu Bar: turn Off Raycast, Logi Options+ and Docker." \
  "$(grep -v '^#' "$DIR/lib/manual-steps.list")"
has "manual step keeps the other icons" "Leave Tailscale, 1Password, Granola, Hammerspoon and Kandji/company agents as they are." \
  "$(grep '^menubar-third-party-hide|' "$DIR/lib/manual-steps.list")"
eq "manual step is by hand" "" "$(awk -F'|' '$1=="menubar-third-party-hide" { print $6 }' "$DIR/lib/manual-steps.list")"

readme="$(cat "$DIR/README.md")"
has "readme names the intended menu bar" \
  "clock, the mode icon, battery percentage, Wi-Fi, Bluetooth and Control Centre" "$readme"
has "readme names kept third-party icons" "Tailscale, 1Password, Granola, Hammerspoon and Kandji/company agents" "$readme"

# ---- repo karabiner.json (the file the directory symlink installs) ----
kb="$(python3 - "$KJ" <<'PY'
import json, sys
g = json.load(open(sys.argv[1])).get("global")
show = g.get("show_in_menu_bar") if isinstance(g, dict) else None
profile = g.get("show_profile_name_in_menu_bar") if isinstance(g, dict) else None
print("ok" if show is False and profile is False else "bad")
PY
)"
eq "repo karabiner.json hides the menu bar icon" ok "$kb"
has "check reads the menu bar flags with python json" "show_profile_name_in_menu_bar" "$(cat "$CHECK")"
has "check passes a hidden karabiner icon" "karabiner.json hides the menu bar icon" "$(cat "$CHECK")"

# ---- macos.sh --list ----------------------------------------------------
list_out="$("$MACOS" --list)"
# shellcheck disable=SC2016  # needles are Markdown from macos.sh --list, compared literally
has "list prints Voice Control" \
  '| Menu Bar | Voice Control | `@host/com.apple.controlcenter VoiceControl` | `8` (Don'"'"'t Show) |' \
  "$list_out"
# shellcheck disable=SC2016
has "list prints Bluetooth" \
  '| Menu Bar | Bluetooth | `@host/com.apple.controlcenter Bluetooth` | `2` (Show in Menu Bar) |' \
  "$list_out"
# shellcheck disable=SC2016
has "list prints battery percentage" \
  '| Menu Bar | Battery percentage | `@host/com.apple.controlcenter BatteryShowPercentage` | `true` (On) |' \
  "$list_out"

# ---- macos.sh with a fake defaults / killall ----------------------------
tmp="$(mktemp -d)"
bin="$tmp/bin"
state="$tmp/state"
dlog="$tmp/defaults.log"
klog="$tmp/killall.log"
mkdir -p "$bin"

BACKUP_BEFORE=""
if [ -d "$DIR/backups" ]; then
  BACKUP_BEFORE="$(find "$DIR/backups" -mindepth 1 -maxdepth 1 -type d -name 'defaults-*' | sort)"
fi
cleanup() {
  local d now
  if [ -d "$DIR/backups" ]; then
    now="$(find "$DIR/backups" -mindepth 1 -maxdepth 1 -type d -name 'defaults-*' | sort)"
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      case "$BACKUP_BEFORE" in
        *"$d"*) ;;
        *) rm -rf "$d" ;;
      esac
    done <<< "$now"
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

cat > "$bin/defaults" <<'EOF'
#!/usr/bin/env bash
# Fake `defaults`. State lines: domain|key|type|value
printf '%s\n' "$*" >> "${DEFAULTS_LOG:?}"
args=("$@")
if [ "${args[0]}" = "-currentHost" ]; then
  args=("${args[@]:1}")
fi
cmd="${args[0]}"
domain="${args[1]:-}"
key="${args[2]:-}"
case "$cmd" in
  read|read-type)
    line="$(awk -F'|' -v d="$domain" -v k="$key" '$1 == d && $2 == k { print; exit }' "${DEFAULTS_STATE:?}")"
    [ -n "$line" ] || exit 1
    if [ "$cmd" = read ]; then
      printf '%s\n' "$(printf '%s\n' "$line" | cut -d'|' -f4-)"
      exit 0
    fi
    typ="$(printf '%s\n' "$line" | cut -d'|' -f3)"
    case "$typ" in
      string) echo "Type is string" ;;
      bool)   echo "Type is boolean" ;;
      int)    echo "Type is integer" ;;
      float)  echo "Type is float" ;;
      *) exit 1 ;;
    esac
    ;;
  export)
    touch "${args[2]}"
    ;;
  write)
    printf 'W|%s|%s|%s|%s\n' "$domain" "$key" "${args[3]:-}" "${args[4]:-}" >> "${DEFAULTS_LOG:?}"
    ;;
  *)
    echo "unexpected defaults $*" >> "${DEFAULTS_LOG:?}"
    exit 1
    ;;
esac
EOF
cat > "$bin/killall" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${KILLALL_LOG:?}"
exit 0
EOF
chmod +x "$bin/defaults" "$bin/killall"

VC="$HOST|VoiceControl"
BT="$HOST|Bluetooth"
BAT="$HOST|BatteryShowPercentage"
: > "$state"
run_macos() {
  : > "$dlog"
  : > "$klog"
  PATH="$bin:$PATH" DEFAULTS_LOG="$dlog" DEFAULTS_STATE="$state" KILLALL_LOG="$klog" \
    "$MACOS" --no-color --yes "$@" --only "$VC" --only "$BT" --only "$BAT"
}
writes() { grep '^W|' "$dlog" || true; }

# Current Mac: Voice Control already hidden, battery percentage already On
# (defaults read prints 1 for boolean true), Bluetooth drifted to Don't Show.
printf '%s\n' \
  'com.apple.controlcenter|VoiceControl|int|8' \
  'com.apple.controlcenter|Bluetooth|int|8' \
  'com.apple.controlcenter|BatteryShowPercentage|bool|1' \
  > "$state"
out="$(run_macos)"
rc=$?
eq "bluetooth drift exits 0" 0 "$rc"
has "boolean 1 battery percentage is already true" \
  "@host/com.apple.controlcenter BatteryShowPercentage — already set: 1 (left alone)" "$out"
has "voice control 8 is already hidden" \
  "@host/com.apple.controlcenter VoiceControl — already set: 8 (left alone)" "$out"
has "bluetooth changes 8 to 2" \
  "@host/com.apple.controlcenter Bluetooth — changed: 8 -> 2" "$out"
eq "only bluetooth is written" \
  "W|com.apple.controlcenter|Bluetooth|-int|2" "$(writes)"
eq "bluetooth repair restarts ControlCenter" "ControlCenter" "$(cat "$klog")"
miss "bluetooth repair does not restart the Dock" "Dock" "$(cat "$klog")"

# Dry-run writes nothing and restarts nothing.
out="$(run_macos --dry-run)"
rc=$?
eq "dry-run exits 0" 0 "$rc"
has "dry-run would show bluetooth" \
  "@host/com.apple.controlcenter Bluetooth — would change: 8 -> 2" "$out"
eq "dry-run does not write" "" "$(writes)"
eq "dry-run does not restart" "" "$(cat "$klog")"

# All three already match. No write, no ControlCenter restart.
printf '%s\n' \
  'com.apple.controlcenter|VoiceControl|int|8' \
  'com.apple.controlcenter|Bluetooth|int|2' \
  'com.apple.controlcenter|BatteryShowPercentage|bool|1' \
  > "$state"
out="$(run_macos)"
rc=$?
eq "already-set exits 0" 0 "$rc"
eq "already-set writes nothing" "" "$(writes)"
eq "already-set restarts nothing" "" "$(cat "$klog")"

# A wrong stored type is skipped, never clobbered, and does not restart.
printf '%s\n' \
  'com.apple.controlcenter|VoiceControl|int|8' \
  'com.apple.controlcenter|Bluetooth|int|2' \
  'com.apple.controlcenter|BatteryShowPercentage|int|1' \
  > "$state"
out="$(run_macos)"
rc=$?
eq "type mismatch still exits 0" 0 "$rc"
has "integer battery percentage is a type mismatch" \
  "@host/com.apple.controlcenter BatteryShowPercentage — type mismatch (expected boolean, found integer); skipping" "$out"
eq "type mismatch writes nothing" "" "$(writes)"
eq "type mismatch restarts nothing" "" "$(cat "$klog")"

printf 'menubar tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
