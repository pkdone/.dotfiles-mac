#!/usr/bin/env bash
#
# Spotlight symbolic hotkey 64 (Command+Space). Fake `defaults` only.
# Enabled parameters (32, 49, 1048576) pass and do not write. Disabled and
# missing fail, and the fix writes -dict-add 64 then activateSettings -u.
# Run: ./tests/spotlight-hotkey.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN="$DIR/scripts/pin-spotlight-hotkey-64.sh"
MACOS="$DIR/macos.sh"

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
# macos.sh writes a restore snapshot under backups/. Remember what was already
# there and delete only directories this run creates.
snapshot_backups() {
  if [ -d "$DIR/backups" ]; then
    find "$DIR/backups" -mindepth 1 -maxdepth 1 -type d -name 'defaults-*' | sort
  fi
}
mkdir -p "$DIR/backups/defaults-keep-spotlight-test"
printf 'keep\n' > "$DIR/backups/defaults-keep-spotlight-test/marker"
BACKUP_BEFORE="$(snapshot_backups)"
sweep_new_backups() {
  local now d
  now="$(snapshot_backups)"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    case "$BACKUP_BEFORE" in
      *"$d"*) ;;
      *) rm -rf "$d" ;;
    esac
  done <<< "$now"
}
cleanup() {
  sweep_new_backups
  rm -rf "$DIR/backups/defaults-keep-spotlight-test" "$tmp"
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

write_state() { # mode
  case "$1" in
    enabled)
      cat > "$state" <<'EOF'
{
    164 =     {
        enabled = 1;
        value =         {
            parameters =             (
                1048592,
                54,
                0
            );
            type = modifier;
        };
    };
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
      ;;
    disabled)
      cat > "$state" <<'EOF'
{
    64 =     {
        enabled = 0;
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
      ;;
    missing)
      cat > "$state" <<'EOF'
{
    164 =     {
        enabled = 1;
        value =         {
            parameters =             (
                1048592,
                54,
                0
            );
            type = modifier;
        };
    };
}
EOF
      ;;
  esac
}

run_pin() {
  : > "$dlog"
  : > "$alog"
  HOME="$home" PATH="$bin:$PATH" DEFAULTS_LOG="$dlog" HOTKEY_STATE="$state" \
    DOTFILES_ACTIVATE_SETTINGS="$bin/activateSettings" ACTIVATE_LOG="$alog" \
    "$@"
}
write_count() { grep -c '^WRITE ' "$dlog" || true; }

has "pin script names activateSettings" \
  "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings" \
  "$(cat "$PIN")"
miss "no Spotlight LaunchAgent plist" "spotlight" "$(ls "$DIR/launchagents")"
miss "login items do not allow a Spotlight agent" "pin-spotlight" "$(cat "$DIR/lib/login-items-allow.list")"
miss "install.sh does not install a Spotlight agent" "pin-spotlight" "$(cat "$DIR/install.sh")"

write_state enabled
out="$(run_pin "$PIN" --check)"
rc=$?
ok "enabled --check exits 0" "$rc"
has "enabled --check says Command+Space" "ok (Command+Space)" "$out"
out="$(run_pin "$PIN")"
rc=$?
ok "enabled pin exits 0" "$rc"
has "enabled pin leaves it alone" "left alone" "$out"
eq "enabled pin does not write" 0 "$(write_count)"
eq "enabled pin does not activate" "" "$(cat "$alog")"

write_state disabled
out="$(run_pin "$PIN" --check)"
rc=$?
eq "disabled --check fails" 1 "$rc"
has "disabled --check names drift" "drift" "$out"
out="$(run_pin "$PIN")"
rc=$?
ok "disabled pin exits 0" "$rc"
eq "disabled pin writes once" 1 "$(write_count)"
has "disabled pin uses dict-add 64" \
  "WRITE write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 " "$(cat "$dlog")"
has "disabled pin writes Command+Space parameters" "parameters = (32, 49, 1048576)" "$(cat "$dlog")"
has "disabled pin keeps it enabled" "enabled = 1" "$(cat "$dlog")"
has "disabled pin uses type standard" "type = standard" "$(cat "$dlog")"
miss "disabled pin does not touch 164" "-dict-add 164" "$(cat "$dlog")"
miss "disabled pin does not touch 190" "-dict-add 190" "$(cat "$dlog")"
eq "disabled pin runs activateSettings -u" "-u" "$(cat "$alog")"

write_state enabled
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
has "missing pin writes the Command+Space dict" "parameters = (32, 49, 1048576)" "$(cat "$dlog")"
eq "missing pin runs activateSettings -u" "-u" "$(cat "$alog")"

# The check in checks/hotkeys.sh uses the same read and the plain-English drift line.
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
  PATH="$bin:$PATH" HOTKEY_STATE="$state" DEFAULTS_LOG="$dlog" check_spotlight_hotkey
}
WHY='Command+Space no longer opens Spotlight (Raycast may have taken it). Fix: System Settings → Keyboard → Keyboard Shortcuts… → Spotlight → tick Show Spotlight search (Command+Space) → Done, or run macconfig --fix'

write_state enabled
out="$(run_check)"
has "check passes when Command+Space is set" "PASS Command+Space opens Spotlight (hotkey 64)" "$out"
miss "check does not drift when enabled" "BAD Command+Space no longer" "$out"

write_state disabled
out="$(run_check)"
has "check names the Raycast takeover when disabled" "BAD $WHY" "$out"

write_state missing
out="$(run_check)"
has "check names the Raycast takeover when 64 is missing" "BAD $WHY" "$out"

# macos.sh writes only when the value differs.
run_macos() {
  : > "$dlog"
  PATH="$bin:/usr/bin:/bin" HOME="$home" DEFAULTS_LOG="$dlog" HOTKEY_STATE="$state" \
    DOTFILES_ACTIVATE_SETTINGS="$bin/activateSettings" ACTIVATE_LOG="$alog" \
    "$MACOS" --no-color --yes --only @spotlight-64
}
write_state enabled
out="$(run_macos)"
rc=$?
ok "macos leaves a correct hotkey" "$rc"
has "macos says left alone" "Spotlight hotkey 64 already Command+Space (left alone)" "$out"
eq "macos does not write when it matches" 0 "$(write_count)"
write_state disabled
out="$(run_macos)"
rc=$?
ok "macos repairs a disabled hotkey" "$rc"
has "macos reports the change" "Spotlight hotkey 64 -> Command+Space" "$out"
eq "macos writes once when it differs" 1 "$(write_count)"
sweep_new_backups
eq "a pre-existing defaults backup is left in place" "keep" \
  "$(cat "$DIR/backups/defaults-keep-spotlight-test/marker")"
eq "this run's defaults backup is removed" "$BACKUP_BEFORE" "$(snapshot_backups)"

printf 'spotlight-hotkey tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
