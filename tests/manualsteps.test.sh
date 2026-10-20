#!/usr/bin/env bash
#
# manualsteps is a fish function for scripts/manual-steps.sh, callable from any
# directory. No arguments runs check; any arguments pass through, and the
# script's exit status comes back. install.sh and macconfig-check.sh symlink
# every fish/functions/*.fish, so this file is installed the same way as
# macconfig. These tests stay off the macOS-only checks.
# Run: ./tests/manualsteps.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FISH_FN="$DIR/fish/functions/manualsteps.fish"

pass=0
fail=0
eq() {  # description expected actual
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}

# ---- fish function -------------------------------------------------------
if [ -f "$FISH_FN" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL: %s exists\n' "$FISH_FN"; fi

# Needles are fixed strings (fish source). Escaping keeps them from expanding here.
if grep -F -q 'function manualsteps --description' "$FISH_FN"; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL: manualsteps has a --description\n'; fi
if grep -F -q "\$HOME/.dotfiles-mac" "$FISH_FN"; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL: manualsteps uses the dotfiles repo path\n'; fi
if grep -F -q 'scripts/manual-steps.sh' "$FISH_FN"; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL: manualsteps runs scripts/manual-steps.sh\n'; fi
if grep -F -q "\$argv" "$FISH_FN"; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL: manualsteps passes arguments through\n'; fi
if grep -F -q 'set args check' "$FISH_FN"; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL: manualsteps with no arguments runs check\n'; fi

# Installed by the same glob as macconfig, not a one-off symlink.
if grep -F -q 'fish/functions/*.fish' "$DIR/install.sh"; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL: install.sh symlinks fish/functions/*.fish\n'; fi
if grep -F -q 'fish/functions/*.fish' "$DIR/checks/symlinks.sh"; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL: macconfig-check.sh checks fish/functions/*.fish links\n'; fi

if command -v fish >/dev/null 2>&1; then
  fish_err="$(fish -n "$FISH_FN" 2>&1)"
  fish_rc=$?
  eq "fish -n manualsteps.fish" "0" "$fish_rc"
  eq "fish -n prints nothing" "" "$fish_err"

  # Stand-in script under a fake HOME: proves the default command, that args
  # and the exit status come back, and that the caller's directory is left alone.
  fake="$(mktemp -d)"
  mkdir -p "$fake/.dotfiles-mac/scripts"
  cat > "$fake/.dotfiles-mac/scripts/manual-steps.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*"
printf '%s' "$PWD" > "$MANUALSTEPS_PWD_OUT"
exit "${MANUALSTEPS_EXIT:-0}"
EOF
  chmod +x "$fake/.dotfiles-mac/scripts/manual-steps.sh"
  pwd_out="$(mktemp)"

  # $1 description, $2 fish arguments (empty = none), $3 expected script args, $4 exit
  invoke() {
    local desc="$1" fish_args="$2" expected="$3" exit_code="$4" out
    : >"$pwd_out"
    out="$(
      HOME="$fake" MANUALSTEPS_PWD_OUT="$pwd_out" MANUALSTEPS_EXIT="$exit_code" \
        fish --no-config -c "cd /tmp; source \"$FISH_FN\"; manualsteps $fish_args; echo STATUS:\$status"
    )"
    eq "$desc" "${expected}
STATUS:${exit_code}" "$out"
    eq "$desc leaves the working directory alone" "/tmp" "$(cat "$pwd_out")"
  }

  invoke "manualsteps with no arguments runs check and returns its status" "" "check" 1
  invoke "manualsteps list passes the argument through" "list" "list" 0
  invoke "manualsteps open passes the argument through" "open" "open" 0
  invoke "manualsteps open --all passes both arguments through" "open --all" "open --all" 0
  invoke "manualsteps check passes the argument through" "check" "check" 7
  invoke "manualsteps --help passes the argument through" "--help" "--help" 0

  rm -rf "$fake" "$pwd_out"
else
  echo "fish not installed — skipped fish -n (CI fish-syntax job still parses *.fish)"
fi

printf 'manualsteps tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
