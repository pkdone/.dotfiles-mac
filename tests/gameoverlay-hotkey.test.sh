#!/usr/bin/env bash
#
# Game Overlay symbolic hotkey 260 (Command+Escape), kept disabled.
# enabled=0 and enabled=false both pass and do not write. Enabled, unbound,
# and missing fail, and the fix writes -dict-add 260 then activateSettings -u.
# A LaunchAgent re-pins it: a software update turns the shortcut back on.
# Run: ./tests/gameoverlay-hotkey.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN="$DIR/scripts/pin-gameoverlay-hotkey-260.sh"
MACOS="$DIR/macos.sh"
PLIST="$DIR/launchagents/com.pdone.pin-gameoverlay-hotkey-260.plist"

pass=0
fail=0
eq() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
has() {
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;; esac
}
miss() {
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n' "$1" "$2" ;;
    *) pass=$((pass + 1)) ;; esac
}
ok() {
  if [ "$2" = 0 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL: %s (status %s)\n' "$1" "$2"; fi
}

tmp="$(mktemp -d)"
home="$tmp/home"
bin="$tmp/bin"
state="$tmp/hotkeys.txt"
dlog="$tmp/defaults.log"
alog="$tmp/activate.log"
mkdir -p "$bin" "$home"
: > "$tmp/made-backups"
note_backups() {
  printf '%s\n' "$1" | awk '/backups -> / { print $NF }' >> "$tmp/made-backups"
}
cleanup() {
  local d
  while IFS= read -r d; do
    [ -n "$d" ] && rm -rf "$d"
  done < "$tmp/made-backups"
  rm -rf "$tmp"
}
trap cleanup EXIT

cat > "$bin/defaults" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DEFAULTS_LOG:?}"
if [ "$1" = "-currentHost" ]; then shift; fi
cmd="$1"
domain="${2:-}"
key="${3:-}"
if [ "$cmd" = read ] && [ "$domain" = com.apple.symbolichotkeys ] && [ "$key" = AppleSymbolicHotKeys ]; then
  cat "${HOTKEY_STATE:?}"
  exit 0
fi
if [ "$cmd" = write ]; then
  printf 'WRITE %s\n' "$*" >> "${DEFAULTS_LOG:?}"
  exit 0
fi
exit 0
EOF
cat > "$bin/activateSettings" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${ACTIVATE_LOG:?}"
exit 0
EOF
chmod +x "$bin/defaults" "$bin/activateSettings"

# mode is off0, offfalse, offFalse, on, unbound, or missing.
write_state() {
  local enabled p1 p2 p3
  case "$1" in
    off0) enabled=0; p1=65535; p2=53; p3=1048576 ;;
    offfalse) enabled=false; p1=65535; p2=53; p3=1048576 ;;
    offFalse) enabled=False; p1=65535; p2=53; p3=1048576 ;;
    on) enabled=1; p1=27; p2=53; p3=1048576 ;;
    unbound) enabled=false; p1=65535; p2=65535; p3=0 ;;
    missing) enabled=""; p1=""; p2=""; p3="" ;;
  esac
  if [ "$1" = missing ]; then
    cat > "$state" <<'EOF'
{
    64 =     {
        enabled = 1;
        value =         {
            parameters =             (
                32,
                49,
                1048576
            );
            type = standard;
        };
    };
}
EOF
    return 0
  fi
  cat > "$state" <<EOF
{
    64 =     {
        enabled = 1;
        value =         {
            parameters =             (
                32,
                49,
                1048576
            );
            type = standard;
        };
    };
    190 =     {
        enabled = 0;
        value =         {
            parameters =             (
                65535,
                65535,
                0
            );
            type = standard;
        };
    };
    260 =     {
        enabled = ${enabled};
        value =         {
            parameters =             (
                ${p1},
                ${p2},
                ${p3}
            );
            type = standard;
        };
    };
}
EOF
}

run_pin() {
  : > "$dlog"
  : > "$alog"
  HOME="$home" PATH="$bin:$PATH" DEFAULTS_LOG="$dlog" HOTKEY_STATE="$state" \
    DOTFILES_ACTIVATE_SETTINGS="$bin/activateSettings" ACTIVATE_LOG="$alog" \
    "$@"
}
write_count() { grep -c '^WRITE ' "$dlog" || true; }

body="$(cat "$PLIST")"
has "pin script names activateSettings" \
  "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings" \
  "$(cat "$PIN")"
has "LaunchAgent plist exists for Game Overlay" "RunAtLoad" "$body"
has "LaunchAgent watches symbolichotkeys via @HOME@" \
  "@HOME@/Library/Preferences/com.apple.symbolichotkeys.plist" "$body"
has "LaunchAgent runs the pin script" "pin-gameoverlay-hotkey-260.sh" "$body"
has "login items allow the Game Overlay agent" \
  "label|com.pdone.pin-gameoverlay-hotkey-260|" "$(cat "$DIR/lib/login-items-allow.list")"

for mode in off0 offfalse offFalse; do
  write_state "$mode"
  out="$(run_pin "$PIN" --check)"
  rc=$?
  ok "$mode --check exits 0" "$rc"
  has "$mode --check says disabled" "ok (disabled)" "$out"
  out="$(run_pin "$PIN")"
  rc=$?
  ok "$mode pin exits 0" "$rc"
  has "$mode pin leaves it alone" "left alone" "$out"
  eq "$mode pin does not write" 0 "$(write_count)"
  eq "$mode pin does not activate" "" "$(cat "$alog")"
done

write_state on
out="$(run_pin "$PIN" --check)"
rc=$?
eq "enabled --check fails" 1 "$rc"
has "enabled --check names drift" "drift" "$out"
out="$(run_pin "$PIN")"
rc=$?
ok "enabled pin exits 0" "$rc"
eq "enabled pin writes once" 1 "$(write_count)"
has "enabled pin uses dict-add 260" \
  "WRITE write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 260 " "$(cat "$dlog")"
has "enabled pin writes the disabled parameters" "parameters = (65535, 53, 1048576)" "$(cat "$dlog")"
has "enabled pin writes enabled = 0" "enabled = 0" "$(cat "$dlog")"
has "enabled pin uses type standard" "type = standard" "$(cat "$dlog")"
miss "enabled pin does not touch 64" "-dict-add 64" "$(cat "$dlog")"
miss "enabled pin does not touch 164" "-dict-add 164" "$(cat "$dlog")"
miss "enabled pin does not touch 190" "-dict-add 190" "$(cat "$dlog")"
eq "enabled pin runs activateSettings -u" "-u" "$(cat "$alog")"

write_state unbound
out="$(run_pin "$PIN")"
rc=$?
ok "unbound disabled pin exits 0" "$rc"
eq "unbound shape is rewritten" 1 "$(write_count)"
has "unbound shape becomes Command+Escape disabled" "parameters = (65535, 53, 1048576)" "$(cat "$dlog")"

write_state off0
out="$(run_pin "$PIN")"
eq "follow-up does not write" 0 "$(write_count)"

write_state missing
out="$(run_pin "$PIN" --check)"
rc=$?
eq "missing --check fails" 1 "$rc"
out="$(run_pin "$PIN")"
rc=$?
ok "missing pin exits 0" "$rc"
eq "missing pin writes once" 1 "$(write_count)"
has "missing pin writes the disabled dict" "parameters = (65535, 53, 1048576)" "$(cat "$dlog")"
eq "missing pin runs activateSettings -u" "-u" "$(cat "$alog")"

export MACCONFIG_CHECKS_DEFINE_ONLY=1 DOTDIR="$DIR"
# shellcheck disable=SC1091
. "$DIR/checks/hotkeys.sh"
unset MACCONFIG_CHECKS_DEFINE_ONLY
hdr() { :; }
fixid() { :; }
CHECKED=0
bad() { printf 'BAD %s\n' "$1"; }
pass() { printf 'PASS %s\n' "$1"; }
run_check() {
  PATH="$bin:$PATH" HOTKEY_STATE="$state" DEFAULTS_LOG="$dlog" check_gameoverlay_hotkey
}

write_state offfalse
out="$(run_check)"
has "check passes when enabled=false" "PASS Game Overlay hotkey 260 = disabled (not Command+Escape)" "$out"
miss "check does not drift when enabled=false" "BAD Game Overlay" "$out"

write_state off0
out="$(run_check)"
has "check passes when enabled=0" "PASS Game Overlay hotkey 260 = disabled (not Command+Escape)" "$out"

write_state on
out="$(run_check)"
has "check names the expected parameters when enabled" \
  "BAD Game Overlay hotkey 260 enabled=1 type=standard parameters=27,53,1048576 (expected enabled=0 type=standard parameters 65535,53,1048576)" "$out"

write_state missing
out="$(run_check)"
has "check drifts when 260 is missing" "BAD Game Overlay hotkey 260 enabled=missing" "$out"

: > "$state"
out="$(run_check)"
has "check drifts when symbolichotkeys is empty" "BAD symbolichotkeys not readable" "$out"

run_macos() {
  : > "$dlog"
  : > "$alog"
  PATH="$bin:/usr/bin:/bin" HOME="$home" DEFAULTS_LOG="$dlog" HOTKEY_STATE="$state" \
    DOTFILES_ACTIVATE_SETTINGS="$bin/activateSettings" ACTIVATE_LOG="$alog" \
    "$MACOS" --no-color --yes "$@"
}
write_state offfalse
out="$(run_macos --only @gameoverlay-260)"
rc=$?
note_backups "$out"
ok "macos leaves a disabled hotkey" "$rc"
has "macos says left alone" "Game Overlay hotkey 260 already disabled (left alone)" "$out"
miss "a matching hotkey does not write a restore snapshot" "backups -> " "$out"
eq "macos does not write when it matches" 0 "$(write_count)"
miss "a match is not called re-asserted" "(re-asserted)" "$out"

write_state on
out="$(run_macos --dry-run --only @gameoverlay-260)"
rc=$?
note_backups "$out"
ok "macos dry-run does not fail" "$rc"
has "macos dry-run names the change" "Game Overlay hotkey 260 -> disabled (dry-run)" "$out"
eq "macos dry-run does not write" 0 "$(write_count)"
miss "dry-run does not snapshot" "backups -> " "$out"

write_state on
out="$(run_macos --only @gameoverlay-260)"
rc=$?
note_backups "$out"
ok "macos repairs an enabled hotkey" "$rc"
has "macos reports the change" "Game Overlay hotkey 260 -> disabled" "$out"
eq "macos writes once when it differs" 1 "$(write_count)"
has "a change names its own restore snapshot" "backups -> " "$out"
eq "a change names one restore snapshot" 1 \
  "$(printf '%s\n' "$out" | grep -c 'backups -> ' || true)"
has "a change notes logout" "Game Overlay shortcut (symbolic hotkey 260)" "$out"

printf 'gameoverlay-hotkey tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
