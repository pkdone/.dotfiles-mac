#!/usr/bin/env bash
#
# Unit tests for lib/ac-sleep.py and the macos.sh sudo guard. Synthetic
# `pmset -g custom` text only — pmset and sudo are fakes, and nothing changes
# a power profile.
# Run: ./tests/ac-sleep.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$DIR/lib/ac-sleep.py"
MACOS="$DIR/macos.sh"
STEPS="$DIR/lib/manual-steps.list"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "ac-sleep tests: python3 not found, skipped"; exit 0; fi

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
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;;
    *) pass=$((pass + 1)) ;; esac
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
chmod +x "$HELPER"

OK_MSG="ok||On mains power the Mac does not sleep on its own (sleep 0). On mains power the display sleeps after 10 minutes. On battery the display sleeps after 2 minutes. On mains power, wake for network access is on. Closing the lid still sleeps the Mac. Battery idle sleep is not changed. macconfig --fix does not change this (it needs sudo)"
field() { # line index — 1 status, 2 commands, 3 message
  printf '%s\n' "$2" | cut -d'|' -f"$1"
}

# Battery block first, the usual pmset -g custom order. Display sleep and
# wake for network access are part of the check. Battery idle sleep is not.
# Sleep On Power Button must not be read as the sleep key.
write_custom() {  # path ac_sleep battery_sleep
  cat > "$1" <<EOF
Battery Power:
 lidwake              1
 displaysleep         2
 Sleep On Power Button 1
 sleep                $3
 lessbright           1
 disksleep            10
AC Power:
 lidwake              1
 displaysleep         10
 Sleep On Power Button 1
 sleep                $2
 womp                 1
 tcpkeepalive         1
 disksleep            10
EOF
}

run() { "$PY" "$HELPER" --text "$1"; }

write_custom "$tmp/off.txt" 0 1
out="$(run "$tmp/off.txt")"; rc=$?
eq "off exits 0" 0 "$rc"
eq "AC sleep 0 passes and ignores battery sleep 1" "$OK_MSG" "$out"

write_custom "$tmp/on.txt" 1 0
out="$(run "$tmp/on.txt")"; rc=$?
eq "on exits 0" 0 "$rc"
eq "AC sleep 1 asks only for sleep 0" "pmset -c sleep 0" "$(field 2 "$out")"
has "AC sleep 1 names the wanted value" "want 0" "$out"
miss "AC sleep 1 does not change display sleep" "displaysleep" "$(field 2 "$out")"

write_custom "$tmp/ten.txt" 10 0
out="$(run "$tmp/ten.txt")"
eq "AC sleep 10 is the sleep key, not displaysleep 10" "pmset -c sleep 0" "$(field 2 "$out")"
has "AC sleep 10 names 10" "but it is 10" "$out"

# AC block first, so a later Battery sleep 0 must not overwrite it.
cat > "$tmp/ac-first.txt" <<'EOF'
AC Power:
 displaysleep         0
 sleep                5
Battery Power:
 sleep                0
 displaysleep         0
EOF
out="$(run "$tmp/ac-first.txt")"
eq "only the AC block's sleep is read when it comes first" "bad" "$(field 1 "$out")"
has "AC-first sleep 5 is the problem" "pmset -c sleep 0" "$(field 2 "$out")"
has "AC-first also wants display sleep 10" "pmset -c displaysleep 10" "$(field 2 "$out")"

cat > "$tmp/button.txt" <<'EOF'
Battery Power:
 displaysleep         2
 sleep                1
AC Power:
 Sleep On Power Button 1
 displaysleep         0
 sleep                0
 womp                 1
EOF
out="$(run "$tmp/button.txt")"
eq "Sleep On Power Button is not the sleep key" "bad" "$(field 1 "$out")"
has "displaysleep 0 is its own command" "pmset -c displaysleep 10" "$(field 2 "$out")"
miss "Sleep On Power Button does not count as sleep" "pmset -c sleep" "$(field 2 "$out")"

cat > "$tmp/spaced.txt" <<'EOF'
Battery Power:
 displaysleep         2
 sleep                45
AC Power:
 displaysleep         10
 sleep                0
 womp                 1
EOF
out="$(run "$tmp/spaced.txt")"
eq "wide spacing still matches the sleep key" "$OK_MSG" "$out"

cat > "$tmp/battery-only.txt" <<'EOF'
Battery Power:
 sleep                0
 displaysleep         2
EOF
out="$(run "$tmp/battery-only.txt")"
eq "battery sleep 0 with no AC block is not a pass" "warn" "$(field 1 "$out")"
has "missing AC block is named" "no 'AC Power:' section" "$out"
eq "missing AC block does not invent a command" "" "$(field 2 "$out")"

cat > "$tmp/no-key.txt" <<'EOF'
Battery Power:
 displaysleep         2
AC Power:
 displaysleep         10
 womp                 1
 Sleep On Power Button 1
 disksleep            10
EOF
out="$(run "$tmp/no-key.txt")"
has "missing AC sleep key warns" "has no sleep value" "$out"
eq "missing sleep key does not invent a command" "warn" "$(field 1 "$out")"
miss "missing key is not a pass" "ok||" "$out"

cat > "$tmp/word.txt" <<'EOF'
AC Power:
 sleep                soon
EOF
out="$(run "$tmp/word.txt")"
has "non-numeric sleep warns" "sleep value 'soon' is not a number" "$out"

printf 'not a power profile\n' > "$tmp/garbage.txt"
out="$(run "$tmp/garbage.txt")"; rc=$?
eq "garbage exits 0" 0 "$rc"
has "garbage is a warning" "no 'AC Power:' section" "$out"

stdin_out="$("$PY" "$HELPER" < "$tmp/off.txt")"
eq "stdin matches --text" "$OK_MSG" "$stdin_out"

out="$(run "$tmp/no-such.txt")"; rc=$?
eq "missing file exits 0" 0 "$rc"
has "missing file is a warning" "could not read pmset -g custom" "$out"

writers="$(grep -nE 'subprocess|os\.system|Popen' "$HELPER" || true)"
eq "helper does not shell out" "" "$writers"

# ---- list / check wiring ------------------------------------------------
eq "ac-sleep where lists the sudo commands" \
  "Terminal: sudo pmset -c sleep 0; sudo pmset -c displaysleep 10; sudo pmset -b displaysleep 2; sudo pmset -c womp 1" \
  "$(awk -F'|' '$1 == "ac-sleep" { print $4; exit }' "$STEPS")"
eq "ac-sleep is checked by macconfig-check.sh" "@macconfig-check.sh" \
  "$(awk -F'|' '$1 == "ac-sleep" { print $6; exit }' "$STEPS")"
title="$(awk -F'|' '$1 == "ac-sleep" { print $3; exit }' "$STEPS")"
has "manual step says the lid still sleeps" "Closing the lid still sleeps the Mac" "$title"
has "manual step says battery idle sleep is not changed" "Battery idle sleep is not changed" "$title"
has "manual step names display sleep" "10 minutes" "$title"
eq "ac-sleep is Needs Paul with no fixer" "PAUL|" \
  "$(awk -F'|' '$1 == "ac-sleep" { print $2 "|" $3; exit }' "$DIR/lib/autofix.list")"

section="$(cat "$DIR/checks/power.sh")"
has "section calls the helper" 'lib/ac-sleep.py' "$section"
has "section tags ac-sleep" 'fixid ac-sleep' "$section"
# shellcheck disable=SC2016
has "not-zero is a warning, not drift" 'bad) warn "$ac_msg"' "$section"
code="$(printf '%s\n' "$section" | grep -v '^[[:space:]]*#')"
miss "section does not run sudo" 'sudo ' "$code"
miss "section does not call macos.sh" 'macos.sh' "$code"

fn="$(awk '/^apply_ac_sleep\(\)/,/^if selected @ac-sleep; then apply_ac_sleep; fi/' "$MACOS")"
# shellcheck disable=SC2016  # the needle is the source text, compared literally
has "macos.sh runs the helper's commands with sudo" 'sudo $c' "$fn"
miss "macos.sh does not hardcode a battery idle-sleep write" 'pmset -b sleep' "$fn"
has "ac sleep is selected like the other @ items" \
  'if selected @ac-sleep; then apply_ac_sleep; fi' "$(cat "$MACOS")"
has "helper names AC display sleep" 'pmset -c displaysleep 10' "$(cat "$HELPER")"
has "helper names battery display sleep" 'pmset -b displaysleep 2' "$(cat "$HELPER")"
has "helper names wake for network access" 'pmset -c womp 1' "$(cat "$HELPER")"

# ---- macos.sh sudo guard, with fake pmset and sudo ----------------------
bin="$tmp/bin"
mkdir -p "$bin"
cat > "$bin/pmset" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${PMSET_LOG:?}"
if [ "${1:-}" = "-g" ] && [ "${2:-}" = "custom" ]; then
  cat "${PMSET_CUSTOM:?}"
  exit 0
fi
echo "unexpected pmset $*" >&2
exit 1
EOF
cat > "$bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SUDO_LOG:?}"
if [ "${1:-}" = "-n" ]; then
  exit "${SUDO_N_RC:-1}"
fi
exit "${SUDO_RC:-0}"
EOF
chmod +x "$bin/pmset" "$bin/sudo"

run_macos() {
  PATH="$bin:$PATH" PMSET_LOG="$1" SUDO_LOG="$2" PMSET_CUSTOM="$3" \
    SUDO_N_RC="${4:-1}" SUDO_RC="${5:-0}" \
    "$MACOS" --no-color --only @ac-sleep "${@:6}"
}

: > "$tmp/pmset.log"
: > "$tmp/sudo.log"
out="$(run_macos "$tmp/pmset.log" "$tmp/sudo.log" "$tmp/off.txt" </dev/null)"; rc=$?
eq "already off exits 0" 0 "$rc"
has "already off does not call sudo" "sleep 0" "$out"
eq "already off never invokes sudo" "" "$(cat "$tmp/sudo.log")"
eq "already off only reads pmset" "-g custom" "$(cat "$tmp/pmset.log")"

: > "$tmp/pmset.log"
: > "$tmp/sudo.log"
out="$(run_macos "$tmp/pmset.log" "$tmp/sudo.log" "$tmp/on.txt" 1 0 --dry-run </dev/null)"; rc=$?
eq "dry-run exits 0" 0 "$rc"
has "dry-run names the command" "dry-run: sudo pmset -c sleep 0" "$out"
eq "dry-run does not invoke sudo" "" "$(cat "$tmp/sudo.log")"

: > "$tmp/pmset.log"
: > "$tmp/sudo.log"
out="$(run_macos "$tmp/pmset.log" "$tmp/sudo.log" "$tmp/on.txt" 1 0 </dev/null)"; rc=$?
eq "no tty skips exits 0" 0 "$rc"
has "no tty says sudo is not available" "sudo not available — skipped" "$out"
has "no tty points at the manual command" "sudo pmset -c sleep 0" "$out"
miss "no tty does not run pmset via sudo" "pmset -c sleep 0" "$(cat "$tmp/sudo.log")"

: > "$tmp/pmset.log"
: > "$tmp/sudo.log"
out="$(run_macos "$tmp/pmset.log" "$tmp/sudo.log" "$tmp/on.txt" 0 0 </dev/null)"; rc=$?
eq "passwordless sudo exits 0" 0 "$rc"
has "passwordless sudo applies the change" "power settings applied (sudo pmset -c sleep 0)" "$out"
eq "passwordless sudo runs exactly pmset -c sleep 0" "pmset -c sleep 0" \
  "$(grep -vx -- '-n true' "$tmp/sudo.log")"
miss "passwordless sudo does not pass -b" '-b' "$(cat "$tmp/sudo.log")"
eq "the write goes through sudo, not a direct pmset -c" "-g custom" "$(cat "$tmp/pmset.log")"

: > "$tmp/pmset.log"
: > "$tmp/sudo.log"
out="$(run_macos "$tmp/pmset.log" "$tmp/sudo.log" "$tmp/on.txt" 0 1 </dev/null)"; rc=$?
eq "failed sudo still exits 0" 0 "$rc"
has "failed sudo points at the manual step" "sudo pmset -c sleep 0 failed — manual step ac-sleep" "$out"

: > "$tmp/pmset.log"
: > "$tmp/sudo.log"
out="$(run_macos "$tmp/pmset.log" "$tmp/sudo.log" "$tmp/battery-only.txt" 0 0 </dev/null)"; rc=$?
eq "unreadable profile exits 0" 0 "$rc"
has "unreadable profile does not guess" "no 'AC Power:' section" "$out"
eq "unreadable profile does not invoke sudo" "" "$(cat "$tmp/sudo.log")"

# A terminal, answering no: sudo isn't wanted. Passwordless sudo is off, so
# the script asks instead of hanging on a password prompt.
# The child gets its own controlling terminal (the test runner often has
# none:. The reply is written when the prompt appears. There is no timer:
# under run-all.sh a busy machine can be slow to reach the question, and a
# deadline would kill the script before it asks.
: > "$tmp/pmset.log"
: > "$tmp/sudo-prompt.log"
prompt_rc=0
prompt_out="$(
  PATH="$bin:$PATH" PMSET_LOG="$tmp/pmset.log" SUDO_LOG="$tmp/sudo-prompt.log" \
    PMSET_CUSTOM="$tmp/on.txt" SUDO_N_RC=1 SUDO_RC=0 \
    "$PY" - "$MACOS" <<'PY'
import errno, os, pty, sys

macos = sys.argv[1]
env = os.environ.copy()
pid, master = pty.fork()
if pid == 0:
    # Replace this process. If exec fails, exit so the child does not fall
    # through into the parent read loop.
    try:
        os.execvpe(macos, [macos, "--no-color", "--only", "@ac-sleep"], env)
    finally:
        os._exit(127)

buf = bytearray()
answered = False
try:
    while True:
        try:
            chunk = os.read(master, 4096)
        except OSError as exc:
            if exc.errno == errno.EINTR:
                continue
            break
        if not chunk:
            break
        buf.extend(chunk)
        if not answered and b"[y/N]" in buf:
            os.write(master, b"n\n")
            answered = True
finally:
    os.close(master)
    os.waitpid(pid, 0)
sys.stdout.buffer.write(buf)
sys.exit(0 if answered else 1)
PY
)" || prompt_rc=$?
eq "prompt was shown" 0 "$prompt_rc"
has "answering no skips because sudo is not wanted" "sudo not wanted" "$prompt_out"
miss "answering no does not run pmset" "pmset -c sleep 0" "$(cat "$tmp/sudo-prompt.log")"

printf 'ac-sleep tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
